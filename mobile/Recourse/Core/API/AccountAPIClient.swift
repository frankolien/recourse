import Foundation

struct AppleAuthChallenge: Decodable, Sendable {
    let nonce: String
    let expiresAt: Int64
    let ttlSecs: Int64
}

struct AccountSessionGrant: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Int64
    let refreshExpiresAt: Int64
    let account: AuthenticatedAccount
}

/// What the server sends to open a WebAuthn ceremony.
///
/// webauthn-rs nests the browser's options under `publicKey`, and the handler adds the
/// challenge id alongside. Only the fields the platform authenticator needs are decoded;
/// the rest (timeouts, algorithm lists) the system supplies itself.
struct PasskeyCeremony: Decodable, Sendable {
    let challengeId: String
    let publicKey: Options

    struct Options: Decodable, Sendable {
        let challenge: String
        let allowCredentials: [Descriptor]?
        let user: User?

        struct Descriptor: Decodable, Sendable { let id: String }
        struct User: Decodable, Sendable {
            let id: String
            let name: String?
            let displayName: String?
        }
    }

    var challengeBytes: Data? { Data(base64URLEncoded: publicKey.challenge) }

    var allowedCredentialIDs: [Data] {
        (publicKey.allowCredentials ?? []).compactMap { Data(base64URLEncoded: $0.id) }
    }

    var userIDBytes: Data? { publicKey.user.flatMap { Data(base64URLEncoded: $0.id) } }
}

enum AccountAPIError: Error, Equatable {
    case invalidResponse
    case rejected(status: Int, message: String)

    var isUnauthorized: Bool {
        if case .rejected(let status, _) = self {
            return status == 401
        }
        return false
    }

    /// Nothing registered under that name yet. A failure for a caller trying to sign in
    /// and a starting point for one offering to create something, so it is the caller's
    /// to interpret rather than a hard error.
    var isNotFound: Bool {
        if case .rejected(let status, _) = self {
            return status == 404
        }
        return false
    }
}

protocol AccountAPI: Sendable {
    func appleChallenge() async throws -> AppleAuthChallenge
    func exchangeAppleCode(
        authorizationCode: String,
        nonce: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AccountSessionGrant
    func exchangeGoogleToken(idToken: String) async throws -> AccountSessionGrant
    func passkeyRegisterStart(email: String) async throws -> PasskeyCeremony
    func passkeyRegisterFinish(
        challengeID: String,
        credential: RegistrationCredential
    ) async throws -> AccountSessionGrant
    func passkeyLoginStart(email: String) async throws -> PasskeyCeremony
    func passkeyLoginFinish(
        challengeID: String,
        credential: AssertionCredential
    ) async throws -> AccountSessionGrant
    func refresh(refreshToken: String) async throws -> AccountSessionGrant
    func me(accessToken: String) async throws -> AuthenticatedAccount
    func updateProfile(
        accessToken: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AuthenticatedAccount
    func logout(accessToken: String) async throws
}

actor AccountAPIClient: AccountAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func appleChallenge() async throws -> AppleAuthChallenge {
        try await send(path: "api/auth/apple/challenge", method: "POST")
    }

    func exchangeAppleCode(
        authorizationCode: String,
        nonce: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AccountSessionGrant {
        let body = AppleExchangeBody(
            authorizationCode: authorizationCode,
            nonce: nonce,
            givenName: givenName,
            familyName: familyName
        )
        return try await send(path: "api/auth/apple", method: "POST", body: body)
    }

    // The backend verifies the Google ID token itself (signature, issuer, audience),
    // so this exchange carries the token and nothing else.
    func exchangeGoogleToken(idToken: String) async throws -> AccountSessionGrant {
        try await send(
            path: "api/auth/google",
            method: "POST",
            body: GoogleExchangeBody(idToken: idToken)
        )
    }

    func passkeyRegisterStart(email: String) async throws -> PasskeyCeremony {
        struct Body: Encodable { let email: String }
        return try await send(
            path: "api/auth/passkey/register/start",
            method: "POST",
            body: Body(email: email)
        )
    }

    func passkeyRegisterFinish(
        challengeID: String,
        credential: RegistrationCredential
    ) async throws -> AccountSessionGrant {
        // Shaped exactly as a browser would send it, because webauthn-rs parses the
        // browser's own type. `extensions` is required even when empty.
        struct Response: Encodable {
            let clientDataJSON: String
            let attestationObject: String
        }
        struct Credential: Encodable {
            let id: String
            let rawId: String
            let type = "public-key"
            let response: Response
            let extensions = [String: String]()
        }
        struct Body: Encodable {
            let challengeId: String
            let credential: Credential
        }
        return try await send(
            path: "api/auth/passkey/register/finish",
            method: "POST",
            body: Body(
                challengeId: challengeID,
                credential: Credential(
                    id: credential.id,
                    rawId: credential.id,
                    response: Response(
                        clientDataJSON: credential.clientDataJSON,
                        attestationObject: credential.attestationObject
                    )
                )
            )
        )
    }

    func passkeyLoginStart(email: String) async throws -> PasskeyCeremony {
        struct Body: Encodable { let email: String }
        return try await send(
            path: "api/auth/passkey/login/start",
            method: "POST",
            body: Body(email: email)
        )
    }

    func passkeyLoginFinish(
        challengeID: String,
        credential: AssertionCredential
    ) async throws -> AccountSessionGrant {
        struct Response: Encodable {
            let clientDataJSON: String
            let authenticatorData: String
            let signature: String
            let userHandle: String?
        }
        struct Credential: Encodable {
            let id: String
            let rawId: String
            let type = "public-key"
            let response: Response
            let extensions = [String: String]()
        }
        struct Body: Encodable {
            let challengeId: String
            let credential: Credential
        }
        return try await send(
            path: "api/auth/passkey/login/finish",
            method: "POST",
            body: Body(
                challengeId: challengeID,
                credential: Credential(
                    id: credential.id,
                    rawId: credential.id,
                    response: Response(
                        clientDataJSON: credential.clientDataJSON,
                        authenticatorData: credential.authenticatorData,
                        signature: credential.signature,
                        userHandle: credential.userHandle
                    )
                )
            )
        )
    }

    func refresh(refreshToken: String) async throws -> AccountSessionGrant {
        try await send(
            path: "api/auth/refresh",
            method: "POST",
            body: RefreshBody(refreshToken: refreshToken)
        )
    }

    func me(accessToken: String) async throws -> AuthenticatedAccount {
        try await send(path: "api/me", method: "GET", bearerToken: accessToken)
    }

    // PUT is full replacement on the backend: a nil field clears the stored name.
    func updateProfile(
        accessToken: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AuthenticatedAccount {
        try await send(
            path: "api/me/profile",
            method: "PUT",
            body: ProfileUpdateBody(givenName: givenName, familyName: familyName),
            bearerToken: accessToken
        )
    }

    func logout(accessToken: String) async throws {
        let _: EmptyResponse = try await send(
            path: "api/auth/logout",
            method: "POST",
            bearerToken: accessToken,
            acceptsEmptyResponse: true
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bearerToken: String? = nil,
        acceptsEmptyResponse: Bool = false
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            bodyData: nil,
            bearerToken: bearerToken,
            acceptsEmptyResponse: acceptsEmptyResponse
        )
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        bearerToken: String? = nil
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            bodyData: try encoder.encode(body),
            bearerToken: bearerToken,
            acceptsEmptyResponse: false
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        bearerToken: String?,
        acceptsEmptyResponse: Bool
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = try? decoder.decode(APIErrorBody.self, from: data)
            throw AccountAPIError.rejected(
                status: httpResponse.statusCode,
                message: errorBody?.error ?? "Request failed"
            )
        }
        if acceptsEmptyResponse, data.isEmpty {
            guard let empty = EmptyResponse() as? Response else {
                throw AccountAPIError.invalidResponse
            }
            return empty
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct AppleExchangeBody: Encodable {
    let authorizationCode: String
    let nonce: String
    let givenName: String?
    let familyName: String?
}

private struct RefreshBody: Encodable {
    let refreshToken: String
}

private struct GoogleExchangeBody: Encodable {
    let idToken: String
}

private struct ProfileUpdateBody: Encodable {
    let givenName: String?
    let familyName: String?
}

private struct APIErrorBody: Decodable {
    let error: String
}

private struct EmptyResponse: Decodable {
    init() {}
}

#if DEBUG
actor PreviewAccountAPI: AccountAPI {
    private let account = AuthenticatedAccount(
        accountID: 1,
        providerUserID: "preview-apple-user",
        email: "frank@recourse.app",
        givenName: "Frank",
        familyName: "Olien"
    )

    func appleChallenge() async throws -> AppleAuthChallenge {
        AppleAuthChallenge(
            nonce: "preview-authentication-nonce",
            expiresAt: 4_000_000_000,
            ttlSecs: 300
        )
    }

    func exchangeAppleCode(
        authorizationCode: String,
        nonce: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AccountSessionGrant {
        grant
    }

    func exchangeGoogleToken(idToken: String) async throws -> AccountSessionGrant {
        grant
    }

    func refresh(refreshToken: String) async throws -> AccountSessionGrant {
        grant
    }

    func me(accessToken: String) async throws -> AuthenticatedAccount {
        account
    }

    func updateProfile(
        accessToken: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AuthenticatedAccount {
        AuthenticatedAccount(
            accountID: account.accountID,
            providerUserID: account.providerUserID,
            email: account.email,
            givenName: givenName,
            familyName: familyName
        )
    }

    func logout(accessToken: String) async throws {}

    // Previews never reach a real authenticator, so these refuse rather than pretend.
    func passkeyRegisterStart(email: String) async throws -> PasskeyCeremony {
        throw AccountAPIError.rejected(status: 503, message: "not available in previews")
    }

    func passkeyRegisterFinish(
        challengeID: String,
        credential: RegistrationCredential
    ) async throws -> AccountSessionGrant {
        throw AccountAPIError.rejected(status: 503, message: "not available in previews")
    }

    func passkeyLoginStart(email: String) async throws -> PasskeyCeremony {
        throw AccountAPIError.rejected(status: 503, message: "not available in previews")
    }

    func passkeyLoginFinish(
        challengeID: String,
        credential: AssertionCredential
    ) async throws -> AccountSessionGrant {
        throw AccountAPIError.rejected(status: 503, message: "not available in previews")
    }

    private var grant: AccountSessionGrant {
        AccountSessionGrant(
            accessToken: "preview-access-token",
            refreshToken: "preview-refresh-token",
            accessExpiresAt: 4_000_000_000,
            refreshExpiresAt: 4_100_000_000,
            account: account
        )
    }
}
#endif
