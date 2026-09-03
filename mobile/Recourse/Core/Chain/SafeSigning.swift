import Foundation
@preconcurrency import BigInt
@preconcurrency import Web3Core

/// The hashes a Safe asks its owners to sign, computed on the phone.
///
/// Three of them: a message (what a cheque or invoice signature wraps), a user
/// operation (what a send signs, in the 4337 module's domain) and a Safe transaction
/// (what a device swap signs). Each is EIP-712 with a domain that is only the chain
/// id and the verifying contract, which is how Safe 1.4.1 and its module define
/// theirs. The formulas are pinned by tests against hashes the live Safe returned.
enum SafeHashing {
    static let domainTypeHash = keccak("EIP712Domain(uint256 chainId,address verifyingContract)")
    static let messageTypeHash = keccak("SafeMessage(bytes message)")
    static let transactionTypeHash = keccak(
        "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
    )
    static let operationTypeHash = keccak(
        "SafeOp(address safe,uint256 nonce,bytes initCode,bytes callData,uint128 verificationGasLimit,uint128 callGasLimit,uint256 preVerificationGas,uint128 maxPriorityFeePerGas,uint128 maxFeePerGas,bytes paymasterAndData,uint48 validAfter,uint48 validUntil,address entryPoint)"
    )

    static func keccak(_ text: String) -> Data {
        Data(text.utf8).sha3(.keccak256)
    }

    static func keccak(_ data: Data) -> Data {
        data.sha3(.keccak256)
    }

    static func domainSeparator(chainID: UInt64, verifyingContract: EthereumAddress) -> Data {
        keccak(domainTypeHash + ABIWord.uint(BigUInt(chainID)) + ABIWord.address(verifyingContract))
    }

    /// What the Safe's `getMessageHash(bytes)` returns for a 32-byte message, which is
    /// how a Safe signs an EIP-712 digest for another contract: the digest is the
    /// message, and both owners sign this.
    static func messageHash(safe: EthereumAddress, chainID: UInt64, digest: Data) -> Data {
        let structHash = keccak(messageTypeHash + keccak(digest))
        return keccak(Data([0x19, 0x01]) + domainSeparator(chainID: chainID, verifyingContract: safe) + structHash)
    }

    /// The hash the 4337 module verifies for a user operation. `validAfter` and
    /// `validUntil` are zero: an operation is good whenever the bundler gets to it.
    static func operationHash(
        module: EthereumAddress,
        chainID: UInt64,
        safe: EthereumAddress,
        nonce: BigUInt,
        callData: Data,
        verificationGasLimit: BigUInt,
        callGasLimit: BigUInt,
        preVerificationGas: BigUInt,
        maxPriorityFeePerGas: BigUInt,
        maxFeePerGas: BigUInt,
        entryPoint: EthereumAddress
    ) -> Data {
        var encoded = operationTypeHash
        encoded += ABIWord.address(safe)
        encoded += ABIWord.uint(nonce)
        encoded += keccak(Data())
        encoded += keccak(callData)
        encoded += ABIWord.uint(verificationGasLimit)
        encoded += ABIWord.uint(callGasLimit)
        encoded += ABIWord.uint(preVerificationGas)
        encoded += ABIWord.uint(maxPriorityFeePerGas)
        encoded += ABIWord.uint(maxFeePerGas)
        encoded += keccak(Data())
        encoded += ABIWord.uint(0)
        encoded += ABIWord.uint(0)
        encoded += ABIWord.address(entryPoint)
        return keccak(Data([0x19, 0x01]) + domainSeparator(chainID: chainID, verifyingContract: module) + keccak(encoded))
    }

    /// The hash of a plain Safe transaction with no gas refund: what `getTransactionHash`
    /// returns for a call the Safe makes to itself, such as an owner swap.
    static func transactionHash(
        safe: EthereumAddress,
        chainID: UInt64,
        to: EthereumAddress,
        data: Data,
        nonce: BigUInt
    ) -> Data {
        var encoded = transactionTypeHash
        encoded += ABIWord.address(to)
        encoded += ABIWord.uint(0)
        encoded += keccak(data)
        encoded += ABIWord.uint(0)
        encoded += ABIWord.uint(0)
        encoded += ABIWord.uint(0)
        encoded += ABIWord.uint(0)
        encoded += ABIWord.address(.zero)
        encoded += ABIWord.address(.zero)
        encoded += ABIWord.uint(nonce)
        return keccak(Data([0x19, 0x01]) + domainSeparator(chainID: chainID, verifyingContract: safe) + keccak(encoded))
    }
}

/// One owner's contribution to a Safe signature.
enum OwnerSignature: Sendable, Equatable {
    /// A secp256k1 signature, 65 bytes, recovery id as 27 or 28.
    case ecdsa(owner: EthereumAddress, signature: Data)
    /// A contract owner's bytes, checked by the owner contract through EIP-1271.
    case contract(owner: EthereumAddress, signature: Data)

    var owner: EthereumAddress {
        switch self {
        case .ecdsa(let owner, _), .contract(let owner, _):
            return owner
        }
    }
}

enum SafeSignatureError: Error, Equatable {
    case malformedECDSA(count: Int)
}

/// Packs owner signatures the way `checkSignatures` reads them: static parts of 65
/// bytes in ascending owner order, contract signatures pointing at their bytes in a
/// dynamic tail.
enum SafeSignatures {
    static func pack(_ signatures: [OwnerSignature]) throws -> Data {
        let ordered = signatures.sorted { $0.owner.value.lowercased() < $1.owner.value.lowercased() }
        var staticPart = Data()
        var dynamicPart = Data()
        let staticLength = 65 * ordered.count

        for entry in ordered {
            switch entry {
            case .ecdsa(_, let signature):
                guard signature.count == 65 else { throw SafeSignatureError.malformedECDSA(count: signature.count) }
                staticPart += normalizedRecoveryID(signature)
            case .contract(let owner, let signature):
                // r names the owner, s points into the tail, v = 0 says "contract".
                staticPart += ABIWord.address(owner)
                staticPart += ABIWord.uint(BigUInt(staticLength + dynamicPart.count))
                staticPart += Data([0])
                dynamicPart += ABIWord.uint(BigUInt(signature.count))
                dynamicPart += signature
                let padding = (32 - signature.count % 32) % 32
                dynamicPart += Data(repeating: 0, count: padding)
            }
        }
        return staticPart + dynamicPart
    }

    /// Safe reads v of 27 or 28 as a plain ecrecover; libraries emit 0 or 1 as often.
    private static func normalizedRecoveryID(_ signature: Data) -> Data {
        var fixed = signature
        let last = fixed.index(before: fixed.endIndex)
        if fixed[last] < 27 { fixed[last] += 27 }
        return fixed
    }
}

/// Calldata the phone builds for the Safe.
enum SafeCalldata {
    /// `executeUserOp(address,uint256,bytes,uint8)` on the 4337 module, through the
    /// Safe's fallback. Operation 0 is a call, 1 a delegatecall.
    static func executeUserOp(to: EthereumAddress, value: BigUInt = 0, data: Data, operation: UInt8 = 0) -> Data {
        var encoded = Data([0x7b, 0xb3, 0x74, 0x28])
        encoded += ABIWord.address(to)
        encoded += ABIWord.uint(value)
        encoded += ABIWord.uint(0x80)
        encoded += ABIWord.uint(BigUInt(operation))
        encoded += ABIWord.uint(BigUInt(data.count))
        encoded += data
        let padding = (32 - data.count % 32) % 32
        encoded += Data(repeating: 0, count: padding)
        return encoded
    }

    /// `swapOwner(address,address,address)`: the call a device rotation makes.
    static func swapOwner(previous: EthereumAddress, old: EthereumAddress, new: EthereumAddress) -> Data {
        Data([0xe3, 0x18, 0xb5, 0x2b]) + ABIWord.address(previous) + ABIWord.address(old) + ABIWord.address(new)
    }
}

/// 32-byte ABI words.
enum ABIWord {
    static func uint(_ value: BigUInt) -> Data {
        let bytes = value.serialize()
        precondition(bytes.count <= 32, "value does not fit a word")
        return Data(repeating: 0, count: 32 - bytes.count) + bytes
    }

    static func address(_ address: EthereumAddress) -> Data {
        let raw = Data(hexString: address.value) ?? Data()
        precondition(raw.count == 20, "address is not 20 bytes")
        return Data(repeating: 0, count: 12) + raw
    }
}

extension EthereumAddress {
    static let zero = EthereumAddress(trusted: "0x0000000000000000000000000000000000000000")
    /// The head of a Safe's owner list; the predecessor of its first owner.
    static let safeSentinel = EthereumAddress(trusted: "0x0000000000000000000000000000000000000001")
}
