import Foundation
import XCTest
@testable import Recourse

final class OrderManifestTests: XCTestCase {
    // Byte-identical to the fixture in backend/src/services/orders.rs; the golden hash
    // was computed with viem keccak256 over the same bytes, so Swift, Rust, and
    // TypeScript provably agree on the orderRef for one document.
    private let fixture = "{\"version\":1,\"chainId\":5042002,\"escrow\":\"0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0\",\"merchant\":\"0xD6c574461d96Ee708f58Fe553049aD4f48BB983A\",\"policyId\":1,\"amount\":\"250000\",\"orderReference\":\"ORDER-1001\",\"itemName\":\"API Credits Pack\",\"description\":\"1,000 cloud compute credits\",\"createdAt\":1784900000}"
    private let goldenOrderRef = "0xa4e970942b2f79b3ef97bd7cbb6a64dd5c92ce63e6c6facc758792f69a88b7cd"

    func testOrderRefMatchesCrossLanguageGolden() {
        XCTAssertEqual(Data(fixture.utf8).keccak256Hash.value, goldenOrderRef)
    }

    func testDecodeVerifiesHashAndParses() throws {
        let manifest = try OrderManifest.decode(
            verifying: Data(fixture.utf8),
            orderReference: ChainHash(trusted: goldenOrderRef)
        )
        XCTAssertEqual(manifest.chainID, 5_042_002)
        XCTAssertEqual(manifest.policyID, 1)
        XCTAssertEqual(manifest.amount, "250000")
        XCTAssertEqual(manifest.itemName, "API Credits Pack")
        XCTAssertNil(manifest.imageHash)
    }

    func testTamperedBytesAreRejected() {
        // One flipped character (the amount) must fail the hash check before parsing.
        let tampered = fixture.replacingOccurrences(of: "250000", with: "250001")
        XCTAssertThrowsError(
            try OrderManifest.decode(
                verifying: Data(tampered.utf8),
                orderReference: ChainHash(trusted: goldenOrderRef)
            )
        ) {
            XCTAssertEqual($0 as? OrderManifestError, .hashMismatch)
        }
    }

    func testCrossCheckAcceptsMatchingRequest() throws {
        let manifest = try OrderManifest.decode(
            verifying: Data(fixture.utf8),
            orderReference: ChainHash(trusted: goldenOrderRef)
        )
        XCTAssertNoThrow(try manifest.crossCheck(against: matchingRequest()))
    }

    func testCrossCheckRejectsEconomicMismatches() throws {
        let manifest = try OrderManifest.decode(
            verifying: Data(fixture.utf8),
            orderReference: ChainHash(trusted: goldenOrderRef)
        )

        XCTAssertThrowsError(
            try manifest.crossCheck(against: matchingRequest(amount: "999999"))
        ) {
            XCTAssertEqual($0 as? OrderManifestError, .fieldMismatch("amount"))
        }
        XCTAssertThrowsError(
            try manifest.crossCheck(
                against: matchingRequest(merchant: "0x1111111111111111111111111111111111111111")
            )
        ) {
            XCTAssertEqual($0 as? OrderManifestError, .fieldMismatch("merchant"))
        }
        XCTAssertThrowsError(
            try manifest.crossCheck(against: matchingRequest(policyID: 9))
        ) {
            XCTAssertEqual($0 as? OrderManifestError, .fieldMismatch("policy"))
        }
    }

    func testEncodedForPublishingRoundtrips() throws {
        let manifest = OrderManifest(
            version: 1,
            chainID: 5_042_002,
            escrow: "0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0",
            merchant: "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A",
            policyID: 2,
            amount: "1250000",
            orderReference: "ORDER-2002",
            itemName: "Design retainer",
            description: "One week of product design",
            imageHash: nil,
            imageContentType: nil,
            createdAt: 1_784_900_500
        )
        let (bytes, orderReference) = try manifest.encodedForPublishing()
        // The published bytes must verify and parse back to the same manifest.
        let decoded = try OrderManifest.decode(verifying: bytes, orderReference: orderReference)
        XCTAssertEqual(decoded, manifest)
    }

    private func matchingRequest(
        amount: String = "250000",
        merchant: String = "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A",
        policyID: UInt64 = 1
    ) throws -> PaymentRequest {
        PaymentRequest(
            version: 2,
            chainID: 5_042_002,
            escrow: EthereumAddress(trusted: "0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0"),
            policyID: policyID,
            merchant: EthereumAddress(trusted: merchant),
            amount: try USDCAmount(baseUnitString: amount),
            orderReference: ChainHash(trusted: goldenOrderRef)
        )
    }
}
