import Foundation

struct EthereumAddress: Codable, Hashable, Sendable, CustomStringConvertible {
    let value: String

    init(_ value: String) throws {
        guard Self.isValid(value) else {
            throw ValidationError.invalidEthereumAddress
        }
        self.value = value
    }

    init(trusted value: String) {
        precondition(Self.isValid(value), "Generated deployment contains an invalid address")
        self.value = value
    }

    var description: String { value }

    var shortened: String {
        "\(value.prefix(6))…\(value.suffix(4))"
    }

    private static func isValid(_ value: String) -> Bool {
        guard value.count == 42, value.hasPrefix("0x") else { return false }
        return value.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}

enum ValidationError: Error, Equatable {
    case invalidEthereumAddress
    case invalidAmount
    case invalidChainHash
    case invalidPaymentRequest
    case unsupportedRequestVersion
    case wrongChain
    case wrongEscrow
}
