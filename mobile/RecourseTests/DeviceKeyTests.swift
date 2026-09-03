import CryptoKit
import XCTest
@testable import Recourse

/// The keychain refuses an unsigned test host, so these run on an in-memory store and
/// prove the encoding and the signing contract. The enclave itself is proven on a phone.
final class DeviceKeyTests: XCTestCase {
    private let store = EphemeralDeviceKeyStore()

    private func makeKey(scope: String = "account-1") -> SecureEnclaveDeviceKey {
        SecureEnclaveDeviceKey(store: store, scope: { scope })
    }

    func testThereIsNoKeyUntilOneIsAsked() async throws {
        let key = makeKey()
        let before = await key.hasKey()
        XCTAssertFalse(before)
        _ = try await key.publicKey()
        let after = await key.hasKey()
        XCTAssertTrue(after)
    }

    func testThePublicKeyIsTwoThirtyTwoByteCoordinates() async throws {
        let key = makeKey()
        let publicKey = try await key.publicKey()
        XCTAssertEqual(publicKey.x.count, 32)
        XCTAssertEqual(publicKey.y.count, 32)
        XCTAssertEqual(publicKey.xHex.count, 66)
        let again = try await key.publicKey()
        XCTAssertEqual(publicKey, again, "asking twice must not mint a second key")
    }

    func testASignatureOverADigestVerifiesAsRawRAndS() async throws {
        let key = makeKey()
        let publicKey = try await key.publicKey()
        let digest = Data(repeating: 0x42, count: 32)

        let signature = try await key.sign(digest: digest)
        XCTAssertEqual(signature.count, 64)

        let point = Data([0x04]) + publicKey.x + publicKey.y
        let verifier = try P256.Signing.PublicKey(x963Representation: point)
        let parsed = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        // The key signed the digest itself, so verification is over the digest as a
        // pre-hashed value, which is what the contract checks too.
        XCTAssertTrue(verifier.isValidSignature(parsed, for: DigestBox(digest)))
        XCTAssertFalse(verifier.isValidSignature(parsed, for: DigestBox(Data(repeating: 0x43, count: 32))))
    }

    func testOnlyThirtyTwoByteDigestsAreSigned() async throws {
        let key = makeKey()
        _ = try await key.publicKey()
        do {
            _ = try await key.sign(digest: Data(repeating: 1, count: 31))
            XCTFail("a 31 byte digest must be refused")
        } catch {
            XCTAssertEqual(error as? DeviceKeyError, .digestNotThirtyTwoBytes)
        }
    }

    func testSigningWithoutAKeyIsNotFound() async throws {
        let key = makeKey()
        do {
            _ = try await key.sign(digest: Data(repeating: 1, count: 32))
            XCTFail("no key was made")
        } catch {
            XCTAssertEqual(error as? DeviceKeyError, .notFound)
        }
    }

    func testTwoAccountsOnOnePhoneGetDifferentKeys() async throws {
        let a = try await makeKey(scope: "account-1").publicKey()
        let b = try await makeKey(scope: "account-2").publicKey()
        XCTAssertNotEqual(a, b)
    }

    func testResetForgetsTheKey() async throws {
        let key = makeKey()
        _ = try await key.publicKey()
        try await key.reset()
        let present = await key.hasKey()
        XCTAssertFalse(present)
    }

    func testDERSignaturesUnpackToSixtyFourBytes() throws {
        let signingKey = P256.Signing.PrivateKey()
        let der = try signingKey.signature(for: Data(repeating: 7, count: 32)).derRepresentation
        let raw = try SecureEnclaveDeviceKey.rawSignature(fromDER: der)
        XCTAssertEqual(raw.count, 64)
        XCTAssertThrowsError(try SecureEnclaveDeviceKey.rawSignature(fromDER: Data([0x30, 0x00])))
    }
}

/// Wraps a precomputed 32-byte digest as a CryptoKit digest so verification checks
/// the signature over those bytes rather than hashing them again.
private struct DigestBox: Digest {
    static var byteCount: Int { 32 }
    private let bytes: Data

    init(_ bytes: Data) { self.bytes = bytes }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
    static func == (lhs: DigestBox, rhs: DigestBox) -> Bool { lhs.bytes == rhs.bytes }
}
