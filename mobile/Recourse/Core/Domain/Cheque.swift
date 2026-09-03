import CryptoSwift
import Foundation

/// A payment someone else cashes when they choose to.
///
/// Not a new mechanism: EIP-3009 `transferWithAuthorization` already is a cheque. The
/// writer signs an authorization, the signature travels, and whoever submits it moves
/// the money. Arc's USDC implements it, so this needs no contract of our own.
///
/// Three properties fall out of the standard, and they are the reasons a cheque is
/// worth having rather than just sending:
///
/// - **It is not bearer.** `to` is signed over, so a leaked cheque still pays only the
///   person it was written to. Losing the signature is not losing the money.
/// - **It expires.** `validBefore` is signed over too, so an uncashed cheque stops
///   being cashable rather than hanging over the writer forever.
/// - **It can be voided.** The nonce is the token's replay guard, and the writer can
///   burn it with `cancelAuthorization` before anyone cashes.
///
/// The money does not move until it is cashed, which is the whole point and also the
/// thing a writer must understand: writing one does not reserve the balance.
struct Cheque: Equatable, Sendable {
    let from: EthereumAddress
    let to: EthereumAddress
    let amount: USDCAmount
    /// Unix seconds. Zero means immediately.
    let validAfter: UInt64
    let validBefore: UInt64
    /// The token's replay guard: 32 random bytes, not a counter. Random because a
    /// sequence would let anyone watching the chain guess the next cheque's nonce and
    /// grief the writer by cancelling it first.
    let nonce: Data

    static func randomNonce() -> Data {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        // A predictable nonce is a cheque someone else can cancel, so failing loudly
        // beats falling back to anything weaker.
        precondition(status == errSecSuccess, "no randomness available for a cheque nonce")
        return bytes
    }
}

/// Builds what the wallet signs, and the digest that signature must cover.
///
/// The digest is computed here rather than left to the signing library so it can be
/// pinned in a test. A wrong digest produces a signature that looks fine locally and is
/// rejected by the token when someone tries to cash it, which is the worst possible
/// place to discover the mistake.
enum ChequeAuthorization {
    /// keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    static let typeHash = "7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267"

    /// keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    static let domainTypeHash = "8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f"

    /// The JSON the signer parses. Field order inside `types` is load bearing: EIP-712
    /// hashes the type string built from it, so reordering changes the digest and
    /// produces a signature the token will not accept.
    static func typedData(
        for cheque: Cheque,
        token: EthereumAddress,
        chainID: Int,
        tokenName: String = "USDC",
        tokenVersion: String = "2"
    ) throws -> Data {
        let payload: [String: Any] = [
            "types": [
                "EIP712Domain": [
                    ["name": "name", "type": "string"],
                    ["name": "version", "type": "string"],
                    ["name": "chainId", "type": "uint256"],
                    ["name": "verifyingContract", "type": "address"],
                ],
                "TransferWithAuthorization": [
                    ["name": "from", "type": "address"],
                    ["name": "to", "type": "address"],
                    ["name": "value", "type": "uint256"],
                    ["name": "validAfter", "type": "uint256"],
                    ["name": "validBefore", "type": "uint256"],
                    ["name": "nonce", "type": "bytes32"],
                ],
            ],
            "primaryType": "TransferWithAuthorization",
            "domain": [
                "name": tokenName,
                "version": tokenVersion,
                "chainId": chainID,
                "verifyingContract": token.value,
            ],
            "message": [
                "from": cheque.from.value,
                "to": cheque.to.value,
                "value": String(cheque.amount.baseUnits),
                "validAfter": String(cheque.validAfter),
                "validBefore": String(cheque.validBefore),
                "nonce": "0x" + cheque.nonce.map { String(format: "%02x", $0) }.joined(),
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    static let cancelTypeHash = "158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429"

    /// What the writer signs to void a cheque they have already handed out.
    ///
    /// A separate struct from the transfer on purpose: the token will not accept a
    /// transfer signature as a cancellation, so a cheque cannot be voided by anyone who
    /// merely holds it.
    static func cancellationTypedData(
        authorizer: EthereumAddress,
        nonce: Data,
        token: EthereumAddress,
        chainID: Int,
        tokenName: String = "USDC",
        tokenVersion: String = "2"
    ) throws -> Data {
        let payload: [String: Any] = [
            "types": [
                "EIP712Domain": [
                    ["name": "name", "type": "string"],
                    ["name": "version", "type": "string"],
                    ["name": "chainId", "type": "uint256"],
                    ["name": "verifyingContract", "type": "address"],
                ],
                "CancelAuthorization": [
                    ["name": "authorizer", "type": "address"],
                    ["name": "nonce", "type": "bytes32"],
                ],
            ],
            "primaryType": "CancelAuthorization",
            "domain": [
                "name": tokenName,
                "version": tokenVersion,
                "chainId": chainID,
                "verifyingContract": token.value,
            ],
            "message": [
                "authorizer": authorizer.value,
                "nonce": "0x" + nonce.map { String(format: "%02x", $0) }.joined(),
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// The EIP-712 domain separator, which the token also computes and stores. Deriving
    /// it rather than reading it from the chain means a cheque can be written offline,
    /// and the test pins it against the value the live contract returns.
    static func domainSeparator(
        token: EthereumAddress,
        chainID: Int,
        tokenName: String = "USDC",
        tokenVersion: String = "2"
    ) -> Data {
        let encoded = hex(domainTypeHash)
            + keccak(Data(tokenName.utf8))
            + keccak(Data(tokenVersion.utf8))
            + word(UInt64(chainID))
            + addressWord(token)
        return keccak(encoded)
    }

    static func structHash(for cheque: Cheque) -> Data {
        let encoded = hex(typeHash)
            + addressWord(cheque.from)
            + addressWord(cheque.to)
            + word(cheque.amount.baseUnits)
            + word(cheque.validAfter)
            + word(cheque.validBefore)
            + cheque.nonce
        return keccak(encoded)
    }

    /// What the signature has to cover: keccak256(0x1901 || domainSeparator || structHash).
    static func digest(for cheque: Cheque, token: EthereumAddress, chainID: Int) -> Data {
        keccak(Data([0x19, 0x01]) + domainSeparator(token: token, chainID: chainID) + structHash(for: cheque))
    }

    static func cancellationDigest(
        authorizer: EthereumAddress,
        nonce: Data,
        token: EthereumAddress,
        chainID: Int
    ) -> Data {
        let structHash = keccak(hex(cancelTypeHash) + addressWord(authorizer) + nonce)
        return keccak(Data([0x19, 0x01]) + domainSeparator(token: token, chainID: chainID) + structHash)
    }

    // MARK: ABI word helpers

    private static func keccak(_ data: Data) -> Data {
        Data(SHA3(variant: .keccak256).calculate(for: Array(data)))
    }

    private static func hex(_ string: String) -> Data {
        var bytes = [UInt8]()
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            bytes.append(UInt8(string[index..<next], radix: 16) ?? 0)
            index = next
        }
        return Data(bytes)
    }

    /// A uint256 is right aligned in 32 bytes.
    private static func word(_ value: UInt64) -> Data {
        var padded = Data(count: 24)
        padded.append(contentsOf: withUnsafeBytes(of: value.bigEndian) { Data($0) })
        return padded
    }

    /// An address is also right aligned in 32 bytes, so the leading 12 are zero.
    private static func addressWord(_ address: EthereumAddress) -> Data {
        Data(count: 12) + hex(String(address.value.dropFirst(2)))
    }
}
