import XCTest
@testable import Recourse

final class VerdictWorkflowTests: XCTestCase {
    func testUnattestedDisputeWaitsForResolveDelay() async throws {
        let payment = DomainFixture.payment(status: .disputed, filedAt: 20_000, claimType: .notDelivered)
        let gateway = FakeContractGateway(payment: payment, delay: 60)

        let readiness = try await VerdictWorkflow(
            gateway: gateway,
            timeProvider: FixedTimeProvider(timestamp: 20_059)
        ).inspect(paymentID: payment.id)

        XCTAssertEqual(readiness, .awaitingAttestation(until: 20_060))
    }

    func testAttestationMakesVerdictImmediatelyReady() async throws {
        let payment = DomainFixture.payment(
            status: .disputed,
            filedAt: 20_000,
            claimType: .notDelivered,
            attestationType: 1
        )
        let gateway = FakeContractGateway(payment: payment, delay: 60)

        let readiness = try await VerdictWorkflow(
            gateway: gateway,
            timeProvider: FixedTimeProvider(timestamp: 20_001)
        ).inspect(paymentID: payment.id)

        XCTAssertEqual(readiness, .ready(DomainFixture.verdict))
    }

    func testResolveConfirmsSettledPaymentAndUsesOnchainPreview() async throws {
        let payment = DomainFixture.payment(status: .disputed, filedAt: 20_000, claimType: .damaged)
        let gateway = FakeContractGateway(payment: payment, delay: 60)

        let result = try await VerdictWorkflow(
            gateway: gateway,
            timeProvider: FixedTimeProvider(timestamp: 20_060)
        ).resolve(paymentID: payment.id)

        XCTAssertEqual(result.payment.status, .settled)
        XCTAssertEqual(result.verdict, DomainFixture.verdict)
        XCTAssertEqual(result.verdict.refundAmount(for: payment.amount), payment.amount)
        let calls = await gateway.recordedCalls()
        XCTAssertEqual(calls, [.resolve])
    }
}
