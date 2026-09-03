import Foundation

/// One token movement on the wallet, as the explorer saw it.
struct TokenTransfer: Identifiable, Equatable, Sendable {
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
/// The v1 `tokentx` action rather than the v2 endpoint: flat strings, one page of two
/// hundred, and a shape that has not changed in years. The app reads history; it does
/// not need pagination cursors for a wallet whose first transaction was this month.
actor ArcscanClient: ExplorerAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func tokenTransfers(for address: EthereumAddress) async throws -> [TokenTransfer] {
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
