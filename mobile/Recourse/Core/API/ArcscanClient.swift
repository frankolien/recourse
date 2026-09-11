import Foundation

/// One token movement on the wallet, as the explorer saw it.
struct TokenTransfer: Identifiable, Codable, Equatable, Sendable {
    let hash: String
    let blockNumber: UInt64
    let timestamp: Date
    /// Lowercased, so every comparison in the app can be a plain equality.
    let from: String
    let to: String
    let value: UInt64
    /// The token contract, lowercased.
    let token: String
    let symbol: String
    /// The function the sending transaction called, without its signature. Empty when
    /// the explorer could not name it. It is what tells a cheque from a send.
    let method: String

    var id: String { "\(hash)-\(from)-\(to)-\(value)" }
}

enum ExplorerAPIError: Error, Equatable {
    case invalidResponse
}

protocol ExplorerAPI: Sendable {
    /// Every ERC-20 transfer touching the address, newest first.
    func tokenTransfers(for address: EthereumAddress) async throws -> [TokenTransfer]
}

/// Blockscout's account API, which is what arcscan runs.
///
/// Asks v2 first and falls back to the v1 `tokentx` action. The v1 shape is the nicer
/// one to read, flat strings that have not changed in years, but the two endpoints are
/// metered separately and the free tier answers v1 with 429 while v2 is still serving.
/// A history that silently stops updating because a rate limit was hit is worse than a
/// slightly fussier decoder, and the fallback means a limit on either one is survivable.
actor ArcscanClient: ExplorerAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func tokenTransfers(for address: EthereumAddress) async throws -> [TokenTransfer] {
        if let rows = try? await modern(address) {
            return rows
        }
        return try await legacy(address)
    }

    /// Blockscout v2. Nested objects and a page cursor that is ignored: a wallet whose
    /// first transaction was this month fits in one page.
    private func modern(_ address: EthereumAddress) async throws -> [TokenTransfer] {
        var components = URLComponents(
            url: baseURL.appending(path: "api/v2/addresses/\(address.value)/token-transfers"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "type", value: "ERC-20")]
        guard let url = components?.url else { throw ExplorerAPIError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExplorerAPIError.invalidResponse
        }
        return try Self.decodeModern(data)
    }

    private func legacy(_ address: EthereumAddress) async throws -> [TokenTransfer] {
        var components = URLComponents(url: baseURL.appending(path: "api"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokentx"),
            URLQueryItem(name: "address", value: address.value),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "offset", value: "200"),
            URLQueryItem(name: "sort", value: "desc"),
        ]
        guard let url = components?.url else { throw ExplorerAPIError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExplorerAPIError.invalidResponse
        }
        return try Self.decode(data)
    }

    /// Separate so a fixture can exercise it without a network.
    static func decodeModern(_ data: Data) throws -> [TokenTransfer] {
        struct Envelope: Decodable {
            let items: [Row]?
        }
        struct Party: Decodable {
            let hash: String
        }
        struct Amount: Decodable {
            let value: String
        }
        struct Token: Decodable {
            let addressHash: String?
            let address: String?
            let symbol: String?

            enum CodingKeys: String, CodingKey {
                case addressHash = "address_hash"
                case address
                case symbol
            }
        }
        struct Row: Decodable {
            let transactionHash: String
            let blockNumber: UInt64
            let timestamp: String
            let from: Party
            let to: Party
            let total: Amount
            let token: Token
            let method: String?

            enum CodingKeys: String, CodingKey {
                case transactionHash = "transaction_hash"
                case blockNumber = "block_number"
                case timestamp, from, to, total, token, method
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ExplorerAPIError.invalidResponse
        }
        return (envelope.items ?? []).compactMap { row in
            guard let value = UInt64(row.total.value),
                  let moment = Self.moment(row.timestamp),
                  let token = row.token.addressHash ?? row.token.address else { return nil }
            return TokenTransfer(
                hash: row.transactionHash.lowercased(),
                blockNumber: row.blockNumber,
                timestamp: moment,
                from: row.from.hash.lowercased(),
                to: row.to.hash.lowercased(),
                value: value,
                token: token.lowercased(),
                symbol: row.token.symbol ?? "",
                // v2 gives a bare selector when it cannot name the function, and a bare
                // selector is not a name, so it is treated as the absence of one.
                method: Self.named(row.method)
            )
        }
    }

    /// v2 timestamps carry fractional seconds, which the plain ISO parser refuses, so
    /// both shapes are tried.
    private static func moment(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// A selector like `0x57ecfd28` is what the explorer says when it does not know the
    /// function, so it is not a method name. A real one is trimmed of its signature.
    private static func named(_ method: String?) -> String {
        guard let method, !method.isEmpty, !method.hasPrefix("0x") else { return "" }
        return method.split(separator: "(").first.map(String.init) ?? ""
    }

    /// Separate so a fixture can exercise it without a network.
    static func decode(_ data: Data) throws -> [TokenTransfer] {
        struct Envelope: Decodable {
            let message: String
            let result: [Row]?
        }
        struct Row: Decodable {
            let hash: String
            let blockNumber: String
            let timeStamp: String
            let from: String
            let to: String
            let value: String
            let contractAddress: String
            let tokenSymbol: String?
            let functionName: String?
        }
        // Blockscout answers an empty history with a different message and a bare
        // array, and some builds send `result` as a string in that case.
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["result"] is String {
                return []
            }
            throw ExplorerAPIError.invalidResponse
        }
        return (envelope.result ?? []).compactMap { row in
            guard let block = UInt64(row.blockNumber),
                  let seconds = TimeInterval(row.timeStamp),
                  let value = UInt64(row.value) else { return nil }
            return TokenTransfer(
                hash: row.hash.lowercased(),
                blockNumber: block,
                timestamp: Date(timeIntervalSince1970: seconds),
                from: row.from.lowercased(),
                to: row.to.lowercased(),
                value: value,
                token: row.contractAddress.lowercased(),
                symbol: row.tokenSymbol ?? "",
                method: (row.functionName ?? "").split(separator: "(").first.map(String.init) ?? ""
            )
        }
    }
}
