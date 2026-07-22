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

enum AccountAPIError: Error, Equatable {
    case invalidResponse
    case rejected(status: Int, message: String)

    var isUnauthorized: Bool {
        if case .rejected(let status, _) = self {
            return status == 401
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
    func refresh(refreshToken: String) async throws -> AccountSessionGrant
    func me(accessToken: String) async throws -> AuthenticatedAccount
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

private struct APIErrorBody: Decodable {
    let error: String
}

private struct EmptyResponse: Decodable {
    init() {}
}
