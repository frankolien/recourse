import Foundation

/// Where to send dollars from a chain that is not Arc.
///
/// The address is a contract whose only power is paying this account on Arc, so it is
/// safe to show and safe to keep. The server asks the chain for it rather than working
/// it out, and so does this: nobody should be told to send money to an address that no
/// authority has confirmed.
struct DepositChainInfo: Codable, Identifiable, Sendable, Equatable {
    let chain: String
    let chainName: String
    let chainID: UInt64
    let token: String

    var id: String { chain }

    enum CodingKeys: String, CodingKey {
        case chain
        case chainName = "chain_name"
        case chainID = "chain_id"
        case token
    }
}

/// One address, good on every chain listed. The vault's code is the same everywhere and
/// the factory sits at one address on every chain, so a person resolves to the same
/// deposit address wherever they send from.
struct DepositAddress: Codable, Sendable, Equatable {
    let address: String
    /// Below this the transfer costs more than it is worth, so it waits for company.
    let minimum: String
    let chains: [DepositChainInfo]

    var isOpen: Bool { !address.isEmpty && !chains.isEmpty }

    /// "Base, Arbitrum and Linea", for a sentence rather than a list.
    var chainSentence: String {
        let names = chains.map(\.chainName)
        guard let last = names.last else { return "" }
        if names.count == 1 { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}

protocol DepositAPI: Sendable {
    func addresses(accessToken: String) async throws -> DepositAddress
}

actor DepositAPIClient: DepositAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func addresses(accessToken: String) async throws -> DepositAddress {
        var request = URLRequest(url: baseURL.appending(path: "api/me/deposit-address"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DepositAddress.self, from: data)
    }
}
