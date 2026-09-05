import Foundation

/// An invoice as the server holds it.
///
/// An invoice is a request for a cheque. The issuer fixes the amount, the payer, the
/// expiry and the nonce; the payer answers by signing an EIP-3009 authorization over
/// exactly those terms, and the issuer submits it to collect. So `signature` is the
/// whole state machine: absent means unanswered, present means the money is collectable
/// and the only remaining question is whether the token has seen it yet.
struct StoredInvoice: Codable, Equatable, Sendable, Identifiable {
    let invoiceId: Int64
    let issuer: String
    let payer: String
    let amount: String
    let validAfter: String
    let validBefore: String
    let nonce: String
    let memo: String
    let signature: String?
    let signedAt: String?
    let cancelledAt: String?
    let createdAt: String

    var id: Int64 { invoiceId }

    var amountBaseUnits: UInt64 { UInt64(amount) ?? 0 }
    var usdc: USDCAmount { USDCAmount(baseUnits: amountBaseUnits) }
    var dueAt: Date { Date(timeIntervalSince1970: TimeInterval(UInt64(validBefore) ?? 0)) }
    var isSigned: Bool { signature != nil }
    var isCancelled: Bool { cancelledAt != nil }

    var nonceBytes: Data { Data(hexString: nonce) ?? Data() }
    var signatureBytes: Data? { signature.flatMap { Data(hexString: $0) } }

    /// The authorization the payer signs, and the issuer later submits.
    ///
    /// `from` is the payer and `to` the issuer, which is the direction that makes an
    /// invoice a pull rather than a push: the money leaves the person who owes it.
    var authorization: Cheque? {
        guard let payer = try? EthereumAddress(payer),
              let issuer = try? EthereumAddress(issuer),
              let validAfter = UInt64(validAfter),
              let validBefore = UInt64(validBefore) else { return nil }
        return Cheque(
            from: payer,
            to: issuer,
            amount: usdc,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonceBytes
        )
    }
}

enum InvoiceAPIError: Error, Equatable {
    case invalidResponse
    case rejected(status: Int, message: String)

    var message: String {
        switch self {
        case .invalidResponse: return "Could not reach invoices."
        case .rejected(_, let message): return message
        }
    }
}

/// What the app sends when issuing one.
struct InvoiceDraft: Encodable, Sendable {
    let issuer: String
    let payer: String
    let amount: String
    let validBefore: String
    let nonce: String
    let memo: String

    init(issuer: EthereumAddress, payer: EthereumAddress, amount: USDCAmount, due: UInt64, nonce: Data, memo: String) {
        self.issuer = issuer.value
        self.payer = payer.value
        self.amount = String(amount.baseUnits)
        validBefore = String(due)
        self.nonce = nonce.hexString
        self.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol InvoiceAPI: Sendable {
    func issue(_ draft: InvoiceDraft, accessToken: String) async throws -> StoredInvoice
    func sign(invoiceID: Int64, signature: Data, accessToken: String) async throws -> StoredInvoice
    func cancel(invoiceID: Int64, accessToken: String) async throws -> StoredInvoice
    func inbox(accessToken: String) async throws -> [StoredInvoice]
    func outbox(accessToken: String) async throws -> [StoredInvoice]
}

actor InvoiceAPIClient: InvoiceAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func issue(_ draft: InvoiceDraft, accessToken: String) async throws -> StoredInvoice {
        try decode(
            try await send(
                path: "api/invoices",
                method: "POST",
                body: try encoder.encode(draft),
                accessToken: accessToken
            )
        )
    }

    func sign(invoiceID: Int64, signature: Data, accessToken: String) async throws -> StoredInvoice {
        struct Body: Encodable { let signature: String }
        return try decode(
            try await send(
                path: "api/invoices/\(invoiceID)/sign",
                method: "POST",
                body: try encoder.encode(Body(signature: signature.hexString)),
                accessToken: accessToken
            )
        )
    }

    func cancel(invoiceID: Int64, accessToken: String) async throws -> StoredInvoice {
        try decode(
            try await send(
                path: "api/invoices/\(invoiceID)/cancel",
                method: "POST",
                body: nil,
                accessToken: accessToken
            )
        )
    }

    func inbox(accessToken: String) async throws -> [StoredInvoice] {
        try decode(try await send(path: "api/invoices/inbox", method: "GET", body: nil, accessToken: accessToken))
    }

    func outbox(accessToken: String) async throws -> [StoredInvoice] {
        try decode(try await send(path: "api/invoices/outbox", method: "GET", body: nil, accessToken: accessToken))
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        guard let decoded = try? decoder.decode(Value.self, from: data) else {
            throw InvoiceAPIError.invalidResponse
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
            throw InvoiceAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw InvoiceAPIError.rejected(
                status: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
                    ?? "Invoices refused that (\(httpResponse.statusCode))."
            )
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        struct Failure: Decodable { let error: String }
        return try? JSONDecoder().decode(Failure.self, from: data).error
    }
}
