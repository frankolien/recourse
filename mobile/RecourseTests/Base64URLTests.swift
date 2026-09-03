import XCTest
@testable import Recourse

/// base64url, which both WebAuthn and PKCE require and neither tolerates a variant of.
///
/// Worth its own tests because the failure mode is silent: standard base64 encodes
/// cleanly, travels cleanly, and is rejected at the far end with an error that says
/// nothing about encoding. Every passkey ceremony depends on this being exactly right.
final class Base64URLTests: XCTestCase {
    func testItSwapsTheTwoAlphabetCharactersThatDifferFromBase64() {
        // 0xFB 0xFF encodes to "+/8=" in standard base64, which exercises both
        // substitutions and the padding strip in one value.
        let data = Data([0xFB, 0xFF])
        XCTAssertEqual(data.base64EncodedString(), "+/8=")
        XCTAssertEqual(data.base64URLEncoded, "-_8")
    }

    func testPaddingIsStripped() {
        XCTAssertEqual(Data([0x01]).base64URLEncoded, "AQ")
        XCTAssertEqual(Data([0x01, 0x02]).base64URLEncoded, "AQI")
        XCTAssertEqual(Data([0x01, 0x02, 0x03]).base64URLEncoded, "AQID")
        XCTAssertFalse(Data([0x01]).base64URLEncoded.contains("="))
    }

    func testDecodingRestoresWhatEncodingDropped() {
        // Every remainder class, since the padding arithmetic is where this goes wrong.
        for length in 1...16 {
            let original = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
            let round = Data(base64URLEncoded: original.base64URLEncoded)
            XCTAssertEqual(round, original, "failed to round trip \(length) bytes")
        }
    }

    func testDecodingAcceptsAValueThatStillCarriesPadding() {
        // Servers are not consistent about stripping it, and a challenge that fails to
        // decode means a ceremony that cannot start.
        XCTAssertEqual(Data(base64URLEncoded: "AQ=="), Data([0x01]))
        XCTAssertEqual(Data(base64URLEncoded: "AQ"), Data([0x01]))
    }

    func testEmptyRoundTrips() {
        XCTAssertEqual(Data().base64URLEncoded, "")
        XCTAssertEqual(Data(base64URLEncoded: ""), Data())
    }

    func testNonsenseDecodesToNothingRatherThanGarbage() {
        XCTAssertNil(Data(base64URLEncoded: "!!!!"))
    }
}
