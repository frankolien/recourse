import Foundation

/// A handle and the address money actually goes to.
struct ResolvedHandle: Codable, Equatable, Sendable {
    /// As its owner capitalised it, which is what the sender should be shown.
    let handle: String
    let address: String
}

enum HandleAPIError: Error, Equatable {
    case invalidResponse
    /// Nobody has claimed this name. Both a failure when sending and a success when
    /// checking whether it is free, so the caller decides which it is.
    case unclaimed
    /// The server answered 404 to the route itself, not to the name. That is a backend
    /// running from before names existed, and the person tapping Claim can do nothing
    /// about it except be told the truth.
    case notOffered
    case rejected(status: Int, message: String)

    var message: String {
        switch self {
        case .invalidResponse:
            return "Could not reach the directory."
        case .unclaimed:
            return "No one is using that name."
        case .notOffered:
            return "Names are not switched on for this server yet."
        case .rejected(_, let message):
            return message
        }
    }
}

protocol HandleAPI: Sendable {
    /// Public: a sender does not need an account to pay someone by name.
    func resolve(handle: String) async throws -> ResolvedHandle
    /// The reverse: names for addresses the app already holds, so a list of cheques
    /// reads as people rather than as hex. Addresses with no name are simply absent.
    func names(for addresses: [String]) async throws -> [String: String]
    func myHandle(accessToken: String) async throws -> ResolvedHandle?
    func claim(handle: String, address: String, accessToken: String) async throws -> ResolvedHandle
}

actor HandleAPIClient: HandleAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func resolve(handle: String) async throws -> ResolvedHandle {
        let name = Self.strip(handle)
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw HandleAPIError.rejected(status: 400, message: "That is not a usable name.")
        }
        return try await send(path: "api/handles/\(encoded)", method: "GET")
    }

    func names(for addresses: [String]) async throws -> [String: String] {
        let unique = Array(Set(addresses.map { $0.lowercased() })).prefix(50)
        guard !unique.isEmpty else { return [:] }
        struct Body: Encodable { let addresses: [String] }
        let found: [ResolvedHandle] = try await send(
            path: "api/handles/names",
            method: "POST",
            bodyData: try encoder.encode(Body(addresses: Array(unique)))
        )
        // Keyed lowercase because everything else in the app compares addresses that
        // way, and a checksummed key would silently miss.
        return Dictionary(
            found.map { ($0.address.lowercased(), $0.handle) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func myHandle(accessToken: String) async throws -> ResolvedHandle? {
        do {
            return try await send(path: "api/me/handle", method: "GET", bearerToken: accessToken)
        } catch HandleAPIError.unclaimed {
            // Not an error at this call site: it is how the app learns the account has
            // not picked a name yet.
            return nil
        }
    }

    func claim(handle: String, address: String, accessToken: String) async throws -> ResolvedHandle {
        struct Body: Encodable {
            let handle: String
            let address: String
        }
        let body = Body(handle: Self.strip(handle), address: address)
        return try await send(
            path: "api/me/handle",
            method: "PUT",
            bodyData: try encoder.encode(body),
            bearerToken: accessToken
        )
    }

    /// The server accepts a leading @ and so does this, but sending it in a URL path
    /// invites an encoding bug for a character that carries no meaning.
    static func strip(_ handle: String) -> String {
        var name = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix("@") { name.removeFirst() }
        return name
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data? = nil,
        bearerToken: String? = nil
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
            throw HandleAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                // Our own handlers explain a 404 in JSON: "no such handle". The
                // framework's 404 for a route that does not exist has no body at all,
                // and the two mean opposite things. Reading the second as the first
                // told someone claiming a name that nobody was using it, which was
                // true, and useless.
                throw Self.errorMessage(from: data) == nil
                    ? HandleAPIError.notOffered
                    : HandleAPIError.unclaimed
            }
            throw HandleAPIError.rejected(
                status: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
                    ?? "The directory refused that (\(httpResponse.statusCode))."
            )
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw HandleAPIError.invalidResponse
        }
        return decoded
    }

    /// The backend explains its refusals in prose worth showing, so surface that rather
    /// than a status code the user cannot act on.
    private static func errorMessage(from data: Data) -> String? {
        struct Failure: Decodable { let error: String }
        return try? JSONDecoder().decode(Failure.self, from: data).error
    }
}
