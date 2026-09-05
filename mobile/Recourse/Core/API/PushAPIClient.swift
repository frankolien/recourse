import Foundation

protocol PushAPI: Sendable {
    func register(token: String, environment: String, accessToken: String) async throws
    func unregister(token: String, accessToken: String) async throws
}

actor PushAPIClient: PushAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func register(token: String, environment: String, accessToken: String) async throws {
        try await send("PUT", body: ["token": token, "environment": environment], accessToken: accessToken)
    }

    func unregister(token: String, accessToken: String) async throws {
        try await send("DELETE", body: ["token": token, "environment": "sandbox"], accessToken: accessToken)
    }

    private func send(_ method: String, body: [String: String], accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/me/push-token"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
