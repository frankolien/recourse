import Foundation
@preconcurrency import web3swift

/// The bytes a Recourse account produces when it acts as a member of an Olien.
///
/// The Safe joins as a CONTRACT signer, so its signer id is its address in a word,
/// its approval is a Safe signature the Olien checks through `isValidSignature`, and
/// its veto is a call the Safe itself makes. Nothing here is signed; these are the
/// values the signing paths agree on, pinned by tests.
enum OlienSigning {
    /// A CONTRACT signer's id: the address in the low 20 bytes of a word (spec §3.1).
    static func signerID(for address: EthereumAddress) -> String {
        "0x" + String(repeating: "0", count: 24) + address.value.dropFirst(2).lowercased()
    }

    /// The first four bytes of keccak256("veto(bytes32)").
    static let vetoSelector = Data([0xfb, 0x6f, 0x93, 0xf9])

    /// `veto(bytes32)` on the Olien, sent from the member's own address.
    static func vetoCalldata(hash: ChainHash) -> Data {
        vetoSelector + bytes(of: hash)
    }

    /// The EIP-712 hash of a proposal's typed data, computed here so the phone can
    /// refuse to sign anything whose hash is not the one the service named.
    static func transactionHash(typedData: Data) throws -> ChainHash {
        let digest = try EIP712Parser.parse(typedData).signHash()
        return try ChainHash(digest.hexString)
    }

    static func bytes(of hash: ChainHash) -> Data {
        let raw = Data(hexString: hash.value) ?? Data()
        precondition(raw.count == 32, "a chain hash is 32 bytes")
        return raw
    }
}
