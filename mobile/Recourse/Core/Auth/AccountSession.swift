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
        api: any AccountAPI = AccountAPIClient(baseURL: URL(string: "http://127.0.0.1:8080")!)
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

            do {
                let profile = try await api.me(accessToken: storedGrant.accessToken)
                try await accept(storedGrant.replacingAccount(profile))
            } catch let error as AccountAPIError where error.isUnauthorized {
                let refreshed = try await api.refresh(refreshToken: storedGrant.refreshToken)
                try await accept(refreshed)
            }
        } catch {
            grant = nil
            account = nil
            try? await store.clear()
        }
    }

    func prepareAppleSignIn() async {
        guard pendingChallenge == nil, !isPreparingAppleSignIn else { return }
        isPreparingAppleSignIn = true
        errorMessage = nil
        defer { isPreparingAppleSignIn = false }

        do {
            pendingChallenge = try await api.appleChallenge()
        } catch {
            errorMessage = "Recourse could not prepare Apple sign-in. Check that the backend is running."
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
