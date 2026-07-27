import AuthenticationServices
import CryptoKit
import Foundation
import Observation

struct AuthenticatedAccount: Codable, Equatable, Sendable {
    let accountID: Int64
    let providerUserID: String
    let email: String?
    let givenName: String?
    let familyName: String?

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"
        case providerUserID = "providerUserId"
        case email
        case givenName
        case familyName
    }

    var displayName: String? {
        [givenName, familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }

    var accountLabel: String {
        email ?? displayName ?? "APPLE ACCOUNT"
    }
}

actor AccountSessionStore {
    private let secureStore: any SecureDataStore
    private let account = "backend-account-session"

    init(secureStore: any SecureDataStore = KeychainStore(service: "com.recourse.buyer.account")) {
        self.secureStore = secureStore
    }

    func save(_ grant: AccountSessionGrant) async throws {
        let data = try JSONEncoder().encode(grant)
        try await secureStore.save(data, account: account)
    }

    func load() async throws -> AccountSessionGrant? {
        guard let data = try await secureStore.load(account: account) else { return nil }
        return try JSONDecoder().decode(AccountSessionGrant.self, from: data)
    }

    func clear() async throws {
        try await secureStore.delete(account: account)
    }
}

@MainActor
protocol AppleCredentialStateChecking {
    func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState
}

@MainActor
final class AppleCredentialStateChecker: AppleCredentialStateChecking {
    private let provider = ASAuthorizationAppleIDProvider()

    func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }
}

@MainActor
@Observable
final class AccountSession {
    private(set) var account: AuthenticatedAccount?
    private(set) var isRestoring = true
    private(set) var isAuthenticating = false
    private(set) var isPreparingAppleSignIn = false
    private(set) var errorMessage: String?

    private let store: AccountSessionStore
    private let credentialChecker: any AppleCredentialStateChecking
    private let api: any AccountAPI
    private var grant: AccountSessionGrant?
    private var pendingChallenge: AppleAuthChallenge?

    init(
        store: AccountSessionStore = AccountSessionStore(),
        credentialChecker: any AppleCredentialStateChecking = AppleCredentialStateChecker(),
        api: any AccountAPI = AccountAPIClient(baseURL: URL(string: "https://api.frankolien.com")!)
    ) {
        self.store = store
        self.credentialChecker = credentialChecker
        self.api = api
    }

    var isAuthenticated: Bool {
        account != nil
    }

    var isAppleSignInReady: Bool {
        pendingChallenge != nil
    }

    /// The in-flight background profile refresh, exposed so tests can await it.
    private(set) var profileRefreshTask: Task<Void, Never>?

    func restore() async {
        guard isRestoring else { return }
        defer { isRestoring = false }

        do {
            guard let storedGrant = try await store.load() else { return }
            let credentialState = try? await credentialChecker.credentialState(
                for: storedGrant.account.providerUserID
            )
            if credentialState == .revoked || credentialState == .notFound {
                try await store.clear()
                return
            }

            // Boot must never wait on the network: trust the cached grant so the
            // app renders immediately, and let the profile refresh (or a forced
            // sign-out on a dead token) catch up in the background.
            try await accept(storedGrant)
            profileRefreshTask = Task { await refreshProfile(from: storedGrant) }
        } catch {
            grant = nil
            account = nil
            try? await store.clear()
        }
    }

    private func refreshProfile(from storedGrant: AccountSessionGrant) async {
        do {
            let profile = try await api.me(accessToken: storedGrant.accessToken)
            try await accept(storedGrant.replacingAccount(profile))
        } catch let error as AccountAPIError where error.isUnauthorized {
            do {
                let refreshed = try await api.refresh(refreshToken: storedGrant.refreshToken)
                try await accept(refreshed)
            } catch {
                grant = nil
                account = nil
                try? await store.clear()
            }
        } catch {
            // Offline or a slow backend keeps the cached session usable.
        }
    }

    func prepareAppleSignIn() async {
        guard pendingChallenge == nil, !isPreparingAppleSignIn else { return }
        isPreparingAppleSignIn = true
        errorMessage = nil
        defer { isPreparingAppleSignIn = false }

        do {
            pendingChallenge = try await api.appleChallenge()
        } catch let error as AccountAPIError {
            switch error {
            case .rejected(_, let message):
                errorMessage = message
            case .invalidResponse:
                errorMessage = "Recourse received an invalid response while preparing Apple sign-in."
            }
        } catch {
            errorMessage = "Recourse could not reach the authentication service. Please try again."
        }
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = pendingChallenge?.nonce.sha256Hex
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, any Error>) {
        errorMessage = nil

        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let codeData = credential.authorizationCode,
                let authorizationCode = String(data: codeData, encoding: .utf8),
                let challenge = pendingChallenge
            else {
                errorMessage = "Apple did not return a complete authorization credential."
                return
            }

            let givenName = credential.fullName?.givenName
            let familyName = credential.fullName?.familyName
            pendingChallenge = nil
            isAuthenticating = true
            Task {
                defer { isAuthenticating = false }
                do {
                    let sessionGrant = try await api.exchangeAppleCode(
                        authorizationCode: authorizationCode,
                        nonce: challenge.nonce,
                        givenName: givenName,
                        familyName: familyName
                    )
                    try await accept(sessionGrant)
                } catch let error as AccountAPIError {
                    switch error {
                    case .rejected(_, let message):
                        errorMessage = message
                    case .invalidResponse:
                        errorMessage = "Recourse received an invalid Apple sign-in response."
                    }
                    await prepareAppleSignIn()
                } catch {
                    errorMessage = "Apple sign-in could not be verified by Recourse. Please try again."
                    await prepareAppleSignIn()
                }
            }

        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            errorMessage = "Sign in with Apple could not be completed. Please try again."
        }
    }

    // Full native Google flow: browser round trip with PKCE, then the backend exchange
    // that mints the same opaque session every other provider uses.
    func signInWithGoogle(clientID: String) async {
        guard !isAuthenticating else { return }
        errorMessage = nil
        let coordinator = GoogleSignInCoordinator(clientID: clientID)
        do {
            let idToken = try await coordinator.signIn()
            isAuthenticating = true
            defer { isAuthenticating = false }
            let sessionGrant = try await api.exchangeGoogleToken(idToken: idToken)
            try await accept(sessionGrant)
        } catch GoogleSignInCoordinator.GoogleSignInError.cancelled {
            // The user closed the sheet; not an error worth a banner.
        } catch let error as AccountAPIError {
            switch error {
            case .rejected(_, let message):
                errorMessage = message
            case .invalidResponse:
                errorMessage = "Recourse received an invalid Google sign-in response."
            }
        } catch {
            errorMessage = "Google sign-in could not be completed. Please try again."
        }
    }

    // Persists the profile on the backend and refreshes the local account from the
    // response. Returns a user-facing error message, or nil on success. Retries once
    // through the refresh token so an expired access token does not surface as a failure.
    func updateProfile(givenName: String?, familyName: String?) async -> String? {
        guard let grant else {
            return "Sign in again to edit your profile."
        }
        do {
            let account = try await api.updateProfile(
                accessToken: grant.accessToken,
                givenName: givenName,
                familyName: familyName
            )
            try await accept(grant.replacingAccount(account))
            return nil
        } catch let error as AccountAPIError where error.isUnauthorized {
            do {
                let refreshed = try await api.refresh(refreshToken: grant.refreshToken)
                let account = try await api.updateProfile(
                    accessToken: refreshed.accessToken,
                    givenName: givenName,
                    familyName: familyName
                )
                try await accept(refreshed.replacingAccount(account))
                return nil
            } catch {
                return "Your session expired. Sign in again to edit your profile."
            }
        } catch let error as AccountAPIError {
            if case .rejected(_, let message) = error {
                return message
            }
            return "Recourse received an invalid response while saving your profile."
        } catch {
            return "Your profile could not be saved. Check your connection and try again."
        }
    }

    func signOut() async {
        if let accessToken = grant?.accessToken {
            try? await api.logout(accessToken: accessToken)
        }
        do {
            try await store.clear()
            grant = nil
            account = nil
            pendingChallenge = nil
            errorMessage = nil
        } catch {
            errorMessage = "Your local session could not be cleared."
        }
    }

    private func accept(_ sessionGrant: AccountSessionGrant) async throws {
        try await store.save(sessionGrant)
        grant = sessionGrant
        account = sessionGrant.account
        errorMessage = nil
    }
}

private extension AccountSessionGrant {
    func replacingAccount(_ account: AuthenticatedAccount) -> Self {
        AccountSessionGrant(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiresAt: accessExpiresAt,
            refreshExpiresAt: refreshExpiresAt,
            account: account
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var sha256Hex: String {
        SHA256.hash(data: Data(utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

#if DEBUG
extension AccountSession {
    static func preview() -> AccountSession {
        AccountSession(api: PreviewAccountAPI())
    }
}
#endif
