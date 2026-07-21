import XCTest
@testable import Recourse

final class DisputeWorkflowTests: XCTestCase {
    func testDisputeWindowIsInclusiveAtExactBoundary() async throws {
        let payment = DomainFixture.payment(paidAt: 10_000)
        let gateway = FakeContractGateway(payment: payment)
        let evidenceRepository = FakeEvidenceRepository()
        let photo = try EvidenceDraft(kind: .photo, content: Data([1, 2, 3]))

        let result = try await DisputeWorkflow(
            gateway: gateway,
            evidenceRepository: evidenceRepository,
            timeProvider: FixedTimeProvider(timestamp: 11_000)
        ).execute(
            paymentID: payment.id,
            buyer: DomainFixture.buyer,
            claimType: .damaged,
            evidence: [photo]
        )

        XCTAssertEqual(result.payment.status, .disputed)
        XCTAssertEqual(result.payment.claimType, .damaged)
        let uploadedKinds = await evidenceRepository.kinds()
        XCTAssertEqual(uploadedKinds, [.photo])
    }

    func testClosedWindowRejectsBeforeEvidenceUpload() async {
        let payment = DomainFixture.payment(paidAt: 10_000)
        let gateway = FakeContractGateway(payment: payment)
        let evidenceRepository = FakeEvidenceRepository()

        do {
            _ = try await DisputeWorkflow(
                gateway: gateway,
                evidenceRepository: evidenceRepository,
                timeProvider: FixedTimeProvider(timestamp: 11_001)
            ).execute(
                paymentID: payment.id,
                buyer: DomainFixture.buyer,
                claimType: .other,
                evidence: []
            )
            XCTFail("Expected closed dispute window")
        } catch {
            XCTAssertEqual(error as? BuyerWorkflowError, .disputeWindowClosed)
        }

        let uploadedKinds = await evidenceRepository.kinds()
        XCTAssertEqual(uploadedKinds, [])
    }

    func testOnlyRecordedBuyerCanFile() async {
        let gateway = FakeContractGateway()
        let evidenceRepository = FakeEvidenceRepository()

        do {
            _ = try await DisputeWorkflow(
                gateway: gateway,
                evidenceRepository: evidenceRepository,
                timeProvider: FixedTimeProvider(timestamp: 10_100)
            ).execute(
                paymentID: 9,
                buyer: DomainFixture.other,
                claimType: .notDelivered,
                evidence: []
            )
            XCTFail("Expected buyer mismatch")
        } catch {
            XCTAssertEqual(error as? BuyerWorkflowError, .notBuyer)
        }
    }
}
