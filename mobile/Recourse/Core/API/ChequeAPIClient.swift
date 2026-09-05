import Foundation

/// A signed cheque as the server holds it.
///
/// The server is a postbox, not an authority. It stores the signature so the person a
/// cheque was written to can find it without the writer staying online, and it can be
/// wrong about everything except the bytes: whether a cheque is still worth anything is
/// a question only the token answers, through `authorizationState`.
struct StoredCheque: Codable, Equatable, Sendable, Identifiable {
    let chequeId: Int64
    let from: String
    let to: String
    /// Decimal strings, because USDC base units outgrow what JSON numbers carry safely.
    let amount: String
    let validAfter: String
    let validBefore: String
    let nonce: String
    let signature: String
    let memo: String?
    let createdAt: String

    var id: Int64 { chequeId }

    var amountBaseUnits: UInt64 { UInt64(amount) ?? 0 }
    var expiresAt: Date { Date(timeIntervalSince1970: TimeInterval(UInt64(validBefore) ?? 0)) }
    var usdc: USDCAmount { USDCAmount(baseUnits: amountBaseUnits) }

    var nonceBytes: Data { Data(hexString: nonce) ?? Data() }
    var signatureBytes: Data { Data(hexString: signature) ?? Data() }

    /// The authorization this row stands for, ready to submit.
    var cheque: Cheque? {
        guard let from = try? EthereumAddress(from),
              let to = try? EthereumAddress(to),
              let validAfter = UInt64(validAfter),
              let validBefore = UInt64(validBefore) else { return nil }
        return Cheque(
            from: from,
            to: to,
            amount: usdc,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonceBytes
        )
    }
}

enum ChequeAPIError: Error, Equatable {
    case invalidResponse
    case rejected(status: Int, message: String)

    var message: String {
        switch self {
        case .invalidResponse: return "Could not reach cheques."
        case .rejected(_, let message): return message
        }
    }
}

protocol ChequeAPI: Sendable {
    func write(_ draft: ChequeDraft, accessToken: String) async throws -> StoredCheque
    func inbox(accessToken: String) async throws -> [StoredCheque]
    func outbox(accessToken: String) async throws -> [StoredCheque]
}

/// What the app sends up after signing.
struct ChequeDraft: Encodable, Sendable {
    let from: String
    let to: String
    let amount: String
    let validAfter: String
    let validBefore: String
    let nonce: String
    let signature: String
    let memo: String?

    init(cheque: Cheque, signature: Data, memo: String?) {
        from = cheque.from.value
        to = cheque.to.value
        amount = String(cheque.amount.baseUnits)
        validAfter = String(cheque.validAfter)
        validBefore = String(cheque.validBefore)
        nonce = cheque.nonce.hexString
        self.signature = signature.hexString
        let trimmed = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.memo = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}

actor ChequeAPIClient: ChequeAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func write(_ draft: ChequeDraft, accessToken: String) async throws -> StoredCheque {
        let data = try await send(
            path: "api/cheques",
            method: "POST",
            body: try encoder.encode(draft),
            accessToken: accessToken
        )
        guard let stored = try? decoder.decode(StoredCheque.self, from: data) else {
            throw ChequeAPIError.invalidResponse
        }
        return stored
    }

    func inbox(accessToken: String) async throws -> [StoredCheque] {
        try await list(path: "api/cheques/inbox", accessToken: accessToken)
    }

    func outbox(accessToken: String) async throws -> [StoredCheque] {
        try await list(path: "api/cheques/outbox", accessToken: accessToken)
    }

    private func list(path: String, accessToken: String) async throws -> [StoredCheque] {
        let data = try await send(path: path, method: "GET", body: nil, accessToken: accessToken)
        guard let decoded = try? decoder.decode([StoredCheque].self, from: data) else {
            throw ChequeAPIError.invalidResponse
        }
        return decoded
    }

    private func send(
        path: String,
        method: String,
        body: Data?,
        accessToken: String
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChequeAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ChequeAPIError.rejected(
                status: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
                    ?? "Cheques refused that (\(httpResponse.statusCode))."
            )
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        struct Failure: Decodable { let error: String }
        return try? JSONDecoder().decode(Failure.self, from: data).error
    }
}
