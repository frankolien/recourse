import XCTest
@testable import Recourse

final class CheckoutWorkflowTests: XCTestCase {
    func testPlannerSkipsApprovalWhenAllowanceCoversAmount() throws {
        let plan = try CheckoutPlanner().plan(
            request: DomainFixture.request,
            policy: DomainFixture.policy,
            balance: USDCAmount(baseUnits: 50_000_000),
            allowance: USDCAmount(baseUnits: 25_000_000),
            configuration: .live
        )

        XCTAssertEqual(plan, .payDirectly)
    }

    func testPlannerRequiresExactApprovalWhenAllowanceIsShort() throws {
        let plan = try CheckoutPlanner().plan(
            request: DomainFixture.request,
            policy: DomainFixture.policy,
            balance: USDCAmount(baseUnits: 50_000_000),
            allowance: USDCAmount(baseUnits: 24_999_999),
            configuration: .live
        )

        XCTAssertEqual(plan, .approveThenPay(approvalAmount: DomainFixture.request.amount))
    }

    func testPlannerRejectsInsufficientBalance() {
        XCTAssertThrowsError(
            try CheckoutPlanner().plan(
                request: DomainFixture.request,
                policy: DomainFixture.policy,
                balance: USDCAmount(baseUnits: 1),
                allowance: USDCAmount(baseUnits: 0),
                configuration: .live
            )
        ) { error in
            XCTAssertEqual(
                error as? BuyerWorkflowError,
                .insufficientBalance(
                    required: DomainFixture.request.amount,
                    available: USDCAmount(baseUnits: 1)
                )
            )
        }
    }

    func testWorkflowApprovesPaysAndReconcilesOnchainPayment() async throws {
        let gateway = FakeContractGateway()
        let result = try await CheckoutWorkflow(gateway: gateway, configuration: .live).execute(
            request: DomainFixture.request,
            buyer: DomainFixture.buyer
        )

        XCTAssertEqual(result.payment.id, 9)
        XCTAssertEqual(result.transactionHash, DomainFixture.paymentHash)
        let calls = await gateway.recordedCalls()
        XCTAssertEqual(calls, [.approve(DomainFixture.request.amount), .pay])
    }

    func testWorkflowStopsWhenApprovalReverts() async {
        let gateway = FakeContractGateway()
        await gateway.setApprovalOutcome(.reverted)

        do {
            _ = try await CheckoutWorkflow(gateway: gateway, configuration: .live).execute(
                request: DomainFixture.request,
                buyer: DomainFixture.buyer
            )
            XCTFail("Expected approval revert")
        } catch {
            XCTAssertEqual(error as? BuyerWorkflowError, .transactionReverted(DomainFixture.approvalHash))
        }

        let calls = await gateway.recordedCalls()
        XCTAssertEqual(calls, [.approve(DomainFixture.request.amount)])
    }
}

private extension FakeContractGateway {
    func setApprovalOutcome(_ outcome: ChainReceipt.Outcome) {
        approvalOutcome = outcome
    }
}
