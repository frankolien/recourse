import Foundation
import XCTest
@testable import Recourse

final class PaymentRequestTests: XCTestCase {
    private let merchant = "0x1111111111111111111111111111111111111111"
    private let orderReference = "0x" + String(repeating: "ab", count: 32)

    func testDecodesValidVersionedRequest() throws {
        let payload = try encodedPayload(chainID: Deployment.chainID, escrow: Deployment.escrow)
        let request = try PaymentRequestDecoder(configuration: .live).decode(base64URL: payload)

        XCTAssertEqual(request.policyID, 3)
        XCTAssertEqual(request.amount.baseUnits, 25_000_000)
        XCTAssertEqual(request.merchant.value, merchant)
        XCTAssertEqual(request.orderReference.value, orderReference)
    }

    func testRejectsWrongChain() throws {
        let payload = try encodedPayload(chainID: 1, escrow: Deployment.escrow)

        XCTAssertThrowsError(try PaymentRequestDecoder(configuration: .live).decode(base64URL: payload)) {
            XCTAssertEqual($0 as? ValidationError, .wrongChain)
        }
    }

    func testRejectsWrongEscrow() throws {
        let payload = try encodedPayload(
            chainID: Deployment.chainID,
            escrow: "0x2222222222222222222222222222222222222222"
        )

        XCTAssertThrowsError(try PaymentRequestDecoder(configuration: .live).decode(base64URL: payload)) {
            XCTAssertEqual($0 as? ValidationError, .wrongEscrow)
        }
    }

    private func encodedPayload(chainID: UInt64, escrow: String) throws -> String {
        let json: [String: Any] = [
            "v": 1,
            "chainId": chainID,
            "escrow": escrow,
            "policyId": 3,
            "merchant": merchant,
            "amount": "25000000",
            "orderRef": orderReference
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
