import XCTest
@testable import Recourse

final class ArcLiveReadTests: XCTestCase {
    func testReadsSeededPolicyPaymentAndVerdictFromArc() async throws {
        guard ProcessInfo.processInfo.environment["ARC_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set ARC_LIVE_TESTS=1 to run Arc integration reads")
        }

        let rpcURL = try XCTUnwrap(
            URL(string: ProcessInfo.processInfo.environment["ARC_RPC_URL"] ?? Deployment.rpcURL)
        )
        let live = AppConfiguration.live
        let configuration = AppConfiguration(
            rpcURL: rpcURL,
            chainID: live.chainID,
            chainName: live.chainName,
            escrowAddress: live.escrowAddress,
            policyRegistryAddress: live.policyRegistryAddress,
            settlementVaultAddress: live.settlementVaultAddress,
            usdcAddress: live.usdcAddress
        )
        let reader = try ArcContractReader.live(configuration: configuration)

        let policy = try await reader.policy(id: 1)
        let payment = try await reader.payment(id: 5)
        let verdict = try await reader.previewVerdict(paymentID: 5)
        let resolveDelay = try await reader.resolveDelay()

        XCTAssertEqual(policy.merchant.value.lowercased(), "0xd70beb0ce6e261fdaa8cb72607316c6bca16a082")
        XCTAssertEqual(policy.disputeWindow, 1_209_600)
        XCTAssertEqual(payment.amount.baseUnits, 250_000)
        XCTAssertEqual(payment.status, .settled)
        XCTAssertEqual(payment.verdictBPS, 10_000)
        XCTAssertEqual(verdict.refundBPS, 10_000)
        XCTAssertTrue(verdict.matched)
        XCTAssertEqual(resolveDelay, 60)
    }
}
