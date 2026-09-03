import Foundation

/// What the server holds for an account: the sealed envelope, and nothing it can read.
struct StoredWalletBackup: Decodable, Equatable, Sendable {
    let envelope: WalletBackup.Envelope
    let address: String
    let updatedAt: String
}

enum WalletBackupAPIError: Error, Equatable {
    case invalidResponse
    /// This account has never stored one. An ordinary answer on a fresh install, not a
    /// failure, which is why it is its own case.
    case none
    case rejected(status: Int, message: String)

    var message: String {
        switch self {
        case .invalidResponse: return "Could not reach recovery."
        case .none: return "This account has no backup yet."
        case .rejected(_, let message): return message
        }
    }
}

protocol WalletBackupAPI: Sendable {
    func fetch(accessToken: String) async throws -> StoredWalletBackup
    func store(envelope: WalletBackup.Envelope, accessToken: String) async throws
    func remove(accessToken: String) async throws
}

actor WalletBackupAPIClient: WalletBackupAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetch(accessToken: String) async throws -> StoredWalletBackup {
        let data = try await send(method: "GET", body: nil, accessToken: accessToken)
        guard let decoded = try? decoder.decode(StoredWalletBackup.self, from: data) else {
            throw WalletBackupAPIError.invalidResponse
        }
        return decoded
    }

    func store(envelope: WalletBackup.Envelope, accessToken: String) async throws {
        _ = try await send(method: "PUT", body: try encoder.encode(envelope), accessToken: accessToken)
    }

    func remove(accessToken: String) async throws {
        _ = try await send(method: "DELETE", body: nil, accessToken: accessToken)
    }

    private func send(method: String, body: Data?, accessToken: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "api/me/wallet-backup"))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WalletBackupAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw WalletBackupAPIError.none }
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw WalletBackupAPIError.rejected(
                status: http.statusCode,
                message: message ?? "Recovery refused that (\(http.statusCode))."
            )
        }
        return data
    }
}
