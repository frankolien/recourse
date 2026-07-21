import Foundation

enum ContractABI: String, CaseIterable, Sendable {
    case erc20 = "IERC20.abi"
    case policyRegistry = "PolicyRegistry.abi"
    case recourseEscrow = "RecourseEscrow.abi"

    func load(from bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: rawValue, withExtension: "json") else {
            throw ContractReadError.missingABI(rawValue)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
