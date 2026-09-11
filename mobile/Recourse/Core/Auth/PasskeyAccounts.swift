import CryptoKit
import Foundation
@preconcurrency import Web3Core

/// Accounts derived from a passkey the way mera does it, so a passkey made on the
/// phone and one made on the web resolve to the same keys.
///
/// The rule is mera's and cannot change without changing every address: the 32
/// PRF bytes are BIP-39 entropy, the mnemonic seeds BIP-32 with an empty passphrase,
/// the EVM key sits at m/44'/60'/0'/0/{index}, and the Ed25519 key at
/// m/44'/501'/{index}'/0' through SLIP-0010. The PRF salt is fixed as well, because
/// a different salt is a different passkey as far as the derivation is concerned.
enum PasskeyAccounts {
    /// sha256("mera.prf.salt.v1"), the salt mera evaluates unless told otherwise.
    static let prfSalt = Data(SHA256.hash(data: Data("mera.prf.salt.v1".utf8)))

    struct Derived: Equatable {
        let mnemonic: String
        let evmPrivateKey: Data
        let evmAddress: EthereumAddress
        let ed25519Seed: Data
        let ed25519PublicKey: Data
    }

    enum DerivationError: Error, Equatable {
        case prfOutputMustBe32Bytes
        case mnemonicFailed
        case seedFailed
        case evmDerivationFailed
        case ed25519Failed
    }

    static func derive(prfOutput: Data, index: UInt32 = 0) throws -> Derived {
        guard prfOutput.count == 32 else { throw DerivationError.prfOutputMustBe32Bytes }
        guard let mnemonic = BIP39.generateMnemonicsFromEntropy(entropy: prfOutput) else {
            throw DerivationError.mnemonicFailed
        }
        guard let seed = BIP39.seedFromMmemonics(mnemonic) else {
            throw DerivationError.seedFailed
        }
        guard let node = HDNode(seed: seed)?.derive(path: "m/44'/60'/0'/0/\(index)"),
              let privateKey = node.privateKey,
              let publicKey = Utilities.privateToPublic(privateKey, compressed: false),
              publicKey.count == 65 else {
            throw DerivationError.evmDerivationFailed
        }
        let addressBytes = SafeHashing.keccak(publicKey.dropFirst()).suffix(20)
        let ed25519Seed = slip10Ed25519(seed: seed, hardenedPath: [44, 501, index, 0])
        guard let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: ed25519Seed) else {
            throw DerivationError.ed25519Failed
        }
        return Derived(
            mnemonic: mnemonic,
            evmPrivateKey: privateKey,
            evmAddress: EthereumAddress(trusted: checksummed(addressBytes)),
            ed25519Seed: ed25519Seed,
            ed25519PublicKey: signing.publicKey.rawRepresentation
        )
    }

    /// SLIP-0010 over Ed25519 only has hardened steps, so the path is the bare
    /// indices and the hardening bit is added here.
    private static func slip10Ed25519(seed: Data, hardenedPath: [UInt32]) -> Data {
        var chain = HMAC<SHA512>.authenticationCode(for: seed, using: SymmetricKey(data: Data("ed25519 seed".utf8)))
        var key = Data(chain.prefix(32))
        var code = Data(chain.suffix(32))
        for step in hardenedPath {
            let index = step | 0x8000_0000
            var data = Data([0x00])
            data.append(key)
            data.append(contentsOf: [
                UInt8(index >> 24), UInt8((index >> 16) & 0xff), UInt8((index >> 8) & 0xff), UInt8(index & 0xff),
            ])
            chain = HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: code))
            key = Data(chain.prefix(32))
            code = Data(chain.suffix(32))
        }
        return key
    }

    /// EIP-55, so the string matches what mera prints and a paste into a block
    /// explorer does not trip its checksum warning.
    static func checksummed(_ address: Data) -> String {
        let lower = address.map { String(format: "%02x", $0) }.joined()
        let hash = SafeHashing.keccak(lower).map { String(format: "%02x", $0) }.joined()
        var out = "0x"
        for (character, nibble) in zip(lower, hash) {
            if let digit = nibble.hexDigitValue, digit >= 8 {
                out.append(character.uppercased())
            } else {
                out.append(character)
            }
        }
        return out
    }
}
