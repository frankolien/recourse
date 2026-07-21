import XCTest
@testable import Recourse

final class ContractABITests: XCTestCase {
    func testReviewedABIsExposeOnlyRequiredReadMethods() throws {
        XCTAssertEqual(
            try functionNames(in: .erc20),
            ["allowance", "approve", "balanceOf"]
        )
        XCTAssertEqual(
            try functionNames(in: .policyRegistry),
            ["getPolicy", "policyHash"]
        )
        XCTAssertEqual(
            try functionNames(in: .recourseEscrow),
            ["fileDispute", "getPayment", "pay", "previewVerdict", "resolve", "resolveDelay"]
        )
    }

    func testPaymentTupleMatchesDeployedStorageView() throws {
        let functions = try functions(in: .recourseEscrow)
        let getPayment = try XCTUnwrap(functions.first { $0["name"] as? String == "getPayment" })
        let outputs = try XCTUnwrap(getPayment["outputs"] as? [[String: Any]])
        let components = try XCTUnwrap(outputs.first?["components"] as? [[String: Any]])

        XCTAssertEqual(
            components.compactMap { $0["name"] as? String },
            [
                "buyer", "merchant", "beneficiary", "policyId", "amount", "shares",
                "paidAt", "filedAt", "claimType", "evidenceMask", "attType", "attValue",
                "evidenceRoot", "verdictBps", "status"
            ]
        )
    }

    private func functionNames(in abi: ContractABI) throws -> [String] {
        try functions(in: abi).compactMap { $0["name"] as? String }.sorted()
    }

    private func functions(in abi: ContractABI) throws -> [[String: Any]] {
        let data = Data(try abi.load().utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}
