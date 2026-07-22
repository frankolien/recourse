import Foundation
import CryptoSwift
@preconcurrency import web3swift

enum EvidenceAuthorizationAction: String, Codable, Sendable {
    case upload = "evidence.upload"
    case manifest = "evidence.manifest"
}

struct EvidenceAuthorizationRequest: Sendable {
    let action: EvidenceAuthorizationAction
    let paymentID: UInt64
    let walletAddress: EthereumAddress
    let chainID: UInt64
    let bodyHash: ChainHash
    let nonce: ChainHash
    let expiresAt: UInt64

    func typedDataJSON() throws -> Data {
        try JSONEncoder().encode(
            TypedDataPayload(
                types: [
                    "EIP712Domain": [
                        .init(name: "name", type: "string"),
                        .init(name: "version", type: "string"),
                        .init(name: "chainId", type: "uint256")
                    ],
                    "Authorization": [
                        .init(name: "action", type: "string"),
                        .init(name: "paymentId", type: "uint256"),
                        .init(name: "walletAddress", type: "address"),
                        .init(name: "chainId", type: "uint256"),
                        .init(name: "bodyHash", type: "bytes32"),
                        .init(name: "nonce", type: "bytes32"),
                        .init(name: "expiresAt", type: "uint256")
                    ]
                ],
                primaryType: "Authorization",
                domain: .init(name: "Recourse", version: "1", chainID: chainID),
                message: .init(
                    action: action.rawValue,
                    paymentID: paymentID,
                    walletAddress: walletAddress.value,
                    chainID: chainID,
                    bodyHash: bodyHash.value,
                    nonce: nonce.value,
                    expiresAt: expiresAt
                )
            )
        )
    }

    func digest() throws -> ChainHash {
        let payload = try EIP712Parser.parse(typedDataJSON())
        return try ChainHash(payload.signHash().hexEncoded)
    }
}

struct EvidenceAuthorizationEnvelope: Encodable, Sendable {
    let request: EvidenceAuthorizationRequest
    let signature: String

    enum CodingKeys: String, CodingKey {
        case action
        case paymentID = "paymentId"
        case walletAddress
        case chainID = "chainId"
        case bodyHash
        case nonce
        case expiresAt
        case signature
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.action.rawValue, forKey: .action)
        try container.encode(request.paymentID, forKey: .paymentID)
        try container.encode(request.walletAddress.value, forKey: .walletAddress)
        try container.encode(request.chainID, forKey: .chainID)
        try container.encode(request.bodyHash.value, forKey: .bodyHash)
        try container.encode(request.nonce.value, forKey: .nonce)
        try container.encode(request.expiresAt, forKey: .expiresAt)
        try container.encode(signature, forKey: .signature)
    }
}

private struct TypedDataPayload: Encodable {
    let types: [String: [TypedDataField]]
    let primaryType: String
    let domain: TypedDataDomain
    let message: TypedDataMessage
}

private struct TypedDataField: Encodable {
    let name: String
    let type: String
}

private struct TypedDataDomain: Encodable {
    let name: String
    let version: String
    let chainID: UInt64

    enum CodingKeys: String, CodingKey {
        case name, version
        case chainID = "chainId"
    }
}

private struct TypedDataMessage: Encodable {
    let action: String
    let paymentID: UInt64
    let walletAddress: String
    let chainID: UInt64
    let bodyHash: String
    let nonce: String
    let expiresAt: UInt64

    enum CodingKeys: String, CodingKey {
        case action
        case paymentID = "paymentId"
        case walletAddress
        case chainID = "chainId"
        case bodyHash, nonce, expiresAt
    }
}

extension Data {
    var keccak256Hash: ChainHash {
        ChainHash(trusted: sha3(.keccak256).hexEncoded)
    }

    var hexEncoded: String {
        "0x" + map { String(format: "%02x", $0) }.joined()
    }
}
