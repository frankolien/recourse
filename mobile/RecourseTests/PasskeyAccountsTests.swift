import XCTest
@testable import Recourse

final class PasskeyAccountsTests: XCTestCase {
    /// Computed independently with @scure/bip39, @scure/bip32 and @noble/curves, the
    /// libraries mera's demo derives with, from PRF output 0x01..0x20. If this
    /// passkey's address on the phone ever differs from its address on the web, it
    /// is this test that has to fail first.
    private let prfOutput = Data((1...32).map { UInt8($0) })

    func testSaltMatchesMera() {
        XCTAssertEqual(
            PasskeyAccounts.prfSalt.hex,
            "896d46ac4ac191885c46137439db7bb52fb05cff3ecd34af7cdae0a1e0c00db9"
        )
    }

    func testDerivesTheSameAccountsAsMera() throws {
        let derived = try PasskeyAccounts.derive(prfOutput: prfOutput)
        XCTAssertEqual(
            derived.mnemonic,
            "absurd avoid scissors anxiety gather lottery category door army half long cage bachelor another expect people blade school educate curtain scrub monitor lady beyond"
        )
        XCTAssertEqual(derived.evmPrivateKey.hex, "7c56100e187f2845a35ce856646662dfc2024be2b4a150b45ad1f62564617128")
        XCTAssertEqual(derived.evmAddress.value, "0x50B240678777451BEfd67B7e8c3b4366482ba8F9")
        XCTAssertEqual(derived.ed25519Seed.hex, "e6ab0994f80a3abf9a1c10d8d27733d24de8c873af6bee177a93a0da5a4b0f79")
        XCTAssertEqual(derived.ed25519PublicKey.hex, "89684d872dd939e6c13b2c9d501465bdfe3546a81d32c2889dca5b6847046100")
    }

    func testIndexMovesTheAccount() throws {
        let first = try PasskeyAccounts.derive(prfOutput: prfOutput)
        let second = try PasskeyAccounts.derive(prfOutput: prfOutput, index: 1)
        XCTAssertNotEqual(first.evmAddress, second.evmAddress)
        XCTAssertNotEqual(first.ed25519PublicKey, second.ed25519PublicKey)
    }

    func testRefusesAnythingButThirtyTwoBytes() {
        XCTAssertThrowsError(try PasskeyAccounts.derive(prfOutput: Data(repeating: 1, count: 31))) { error in
            XCTAssertEqual(error as? PasskeyAccounts.DerivationError, .prfOutputMustBe32Bytes)
        }
    }

    func testChecksumIsEIP55() {
        let bytes = Data([0x5a, 0xae, 0xb6, 0x05, 0x3f, 0x3e, 0x94, 0xc9, 0xb9, 0xa0, 0x9f, 0x33, 0x66, 0x94, 0x35, 0xe7, 0xef, 0x1b, 0xea, 0xed])
        XCTAssertEqual(PasskeyAccounts.checksummed(bytes), "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
