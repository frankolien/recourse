import Foundation

struct ChainHash: Codable, Hashable, Sendable, CustomStringConvertible {
    let value: String

    init(_ value: String) throws {
        guard value.count == 66,
              value.hasPrefix("0x"),
              value.dropFirst(2).allSatisfy(\.isHexDigit) else {
            throw ValidationError.invalidChainHash
        }
        self.value = value
    }

    init(trusted value: String) {
        precondition(
            value.count == 66 && value.hasPrefix("0x") && value.dropFirst(2).allSatisfy(\.isHexDigit),
            "Trusted chain hash is invalid"
        )
        self.value = value
    }

    var description: String { value }

    var shortened: String {
        "\(value.prefix(8))…\(value.suffix(6))"
    }
}
