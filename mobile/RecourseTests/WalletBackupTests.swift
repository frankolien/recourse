import XCTest
@testable import Recourse

final class WalletBackupTests: XCTestCase {
    private let key = Data((0..<32).map { UInt8($0 &+ 1) })
    private let address = "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A"

    // Scrypt at the shipping cost takes seconds by design, so format and behaviour
    // tests run it cheap. testTheShippingCostIsActuallyUsable pays the real price once,
    // which is what proves the parameters the app ships with are the ones that work.
    private func sealed(pin: String) throws -> WalletBackup.Envelope {
        try WalletBackup.seal(privateKey: key, pin: pin, address: address, n: 1024, r: 8, p: 1)
    }

    func testTheShippingCostIsActuallyUsable() throws {
        let started = Date()
        let envelope = try WalletBackup.seal(privateKey: key, pin: "123456", address: address)
        XCTAssertEqual(envelope.n, WalletBackup.scryptN)
        XCTAssertEqual(try WalletBackup.open(envelope, pin: "123456"), key)
        // Two derivations at 32 MB each. Generous, because CI machines are slow and the
        // assertion that matters is that it finishes at all, not that it is fast.
        XCTAssertLessThan(Date().timeIntervalSince(started), 30)
    }

    func testTheRightPINReturnsTheExactKey() throws {
        let envelope = try sealed(pin: "123456")
        XCTAssertEqual(try WalletBackup.open(envelope, pin: "123456"), key)
    }

    func testAWrongPINFailsRatherThanReturningRubbish() throws {
        let envelope = try sealed(pin: "123456")
        // AES-GCM authenticates, so a wrong key is a detected failure and never a
        // plausible-looking private key that would send funds into nowhere.
        XCTAssertThrowsError(try WalletBackup.open(envelope, pin: "123457")) { error in
            XCTAssertEqual(error as? WalletBackup.Failure, .wrongPIN)
        }
    }

    func testTheServerNeverHoldsTheKeyOrThePIN() throws {
        let envelope = try sealed(pin: "123456")
        let json = try JSONEncoder().encode(envelope)
        let text = String(decoding: json, as: UTF8.self)

        // Everything that leaves the device, checked for the two things that must
        // never be in it.
        XCTAssertFalse(text.contains("123456"), "the PIN must not appear in the blob")
        XCTAssertFalse(
            envelope.ciphertext.contains(key.base64EncodedString()),
            "the key must not appear in the blob"
        )
        XCTAssertFalse(text.lowercased().contains(key.map { String(format: "%02x", $0) }.joined()))
    }

    func testEverySealIsDifferentForTheSamePINAndKey() throws {
        let first = try sealed(pin: "123456")
        let second = try sealed(pin: "123456")
        // A fresh salt and nonce each time: identical blobs would leak that two
        // accounts share a PIN, and would let one precomputation open both.
        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.ciphertext, second.ciphertext)
        XCTAssertEqual(try WalletBackup.open(first, pin: "123456"), key)
        XCTAssertEqual(try WalletBackup.open(second, pin: "123456"), key)
    }

    func testAShortPINIsRefusedBeforeAnythingIsEncrypted() {
        XCTAssertThrowsError(try sealed(pin: "12345")) { error in
            XCTAssertEqual(error as? WalletBackup.Failure, .pinTooShort)
        }
    }

    func testALongerPassphraseIsAccepted() throws {
        let envelope = try WalletBackup.seal(
            privateKey: key,
            pin: "correct horse battery staple",
            address: address,
            n: 1024, r: 8, p: 1
        )
        XCTAssertEqual(try WalletBackup.open(envelope, pin: "correct horse battery staple"), key)
    }

    func testTheAddressIsCarriedSoARestoreCanNameTheWalletBeforeAskingForAPIN() throws {
        let envelope = try sealed(pin: "123456")
        XCTAssertEqual(envelope.address, address.lowercased())
    }

    func testAFutureFormatIsRefusedRatherThanMisread() throws {
        var envelope = try sealed(pin: "123456")
        envelope.version = 2
        // Passkey PRF will replace the KDF, so an old build must say it cannot read a
        // new blob rather than deriving the wrong key from it.
        XCTAssertThrowsError(try WalletBackup.open(envelope, pin: "123456")) { error in
            XCTAssertEqual(error as? WalletBackup.Failure, .unsupportedVersion(2))
        }
    }

    func testATamperedCiphertextIsRejected() throws {
        var envelope = try sealed(pin: "123456")
        var raw = Data(base64Encoded: envelope.ciphertext)!
        raw[0] ^= 0xFF
        envelope.ciphertext = raw.base64EncodedString()
        // The tag is what makes a hostile server unable to hand back a key of its
        // choosing, so this must fail rather than decrypt to something.
        XCTAssertThrowsError(try WalletBackup.open(envelope, pin: "123456"))
    }

    func testAnEnvelopeSurvivesTheRoundTripTheBackendPutsItThrough() throws {
        let envelope = try sealed(pin: "123456")
        let decoded = try JSONDecoder().decode(
            WalletBackup.Envelope.self,
            from: try JSONEncoder().encode(envelope)
        )
        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(try WalletBackup.open(decoded, pin: "123456"), key)
    }

    func testStoredParametersAreUsedSoOldBackupsStillOpenAfterACostIncrease() throws {
        var envelope = try sealed(pin: "123456")
        // Rewriting N without re-sealing simulates a build that raised the cost; the
        // envelope's own value must win or every existing backup would be bricked.
        let openedWithStoredCost = try WalletBackup.open(envelope, pin: "123456")
        XCTAssertEqual(openedWithStoredCost, key)
        envelope.n = envelope.n * 2
        XCTAssertThrowsError(try WalletBackup.open(envelope, pin: "123456"))
    }
}
