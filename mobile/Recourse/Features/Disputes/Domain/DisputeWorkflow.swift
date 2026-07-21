import Foundation

enum DisputeProgress: Equatable, Sendable {
    case validating
    case uploading(completed: Int, total: Int)
    case filing
    case submitted(ChainHash)
    case confirmed(paymentID: UInt64, transactionHash: ChainHash)
}

struct DisputeResult: Equatable, Sendable {
    let payment: PaymentRecord
    let uploadedEvidence: [UploadedEvidence]
    let transactionHash: ChainHash
}

struct DisputeWorkflow: Sendable {
    private let gateway: any ContractGateway
    private let evidenceRepository: any EvidenceRepository
    private let timeProvider: any UnixTimeProvider

    init(
        gateway: any ContractGateway,
        evidenceRepository: any EvidenceRepository,
        timeProvider: any UnixTimeProvider
    ) {
        self.gateway = gateway
        self.evidenceRepository = evidenceRepository
        self.timeProvider = timeProvider
    }

    func execute(
        paymentID: UInt64,
        buyer: EthereumAddress,
        claimType: ClaimType,
        evidence drafts: [EvidenceDraft],
        onProgress: @escaping @Sendable (DisputeProgress) async -> Void = { _ in }
    ) async throws -> DisputeResult {
        await onProgress(.validating)
        let payment = try await gateway.payment(id: paymentID)
        guard payment.buyer == buyer else { throw BuyerWorkflowError.notBuyer }
        guard payment.status == .paid else { throw BuyerWorkflowError.paymentNotOpen }

        let policy = try await gateway.policy(id: payment.policyID)
        let closesAt = payment.paidAt.addingReportingOverflow(policy.disputeWindow)
        guard !closesAt.overflow, timeProvider.now() <= closesAt.partialValue else {
            throw BuyerWorkflowError.disputeWindowClosed
        }

        var uploaded: [UploadedEvidence] = []
        uploaded.reserveCapacity(drafts.count)
        for draft in drafts {
            uploaded.append(try await evidenceRepository.upload(draft))
            await onProgress(.uploading(completed: uploaded.count, total: drafts.count))
        }

        await onProgress(.filing)
        let transactionHash = try await gateway.fileDispute(
            paymentID: paymentID,
            claimType: claimType,
            evidence: uploaded
        )
        await onProgress(.submitted(transactionHash))
        let receipt = try await gateway.waitForReceipt(transactionHash: transactionHash)
        guard receipt.outcome == .confirmed else {
            throw BuyerWorkflowError.transactionReverted(transactionHash)
        }

        let disputedPayment = try await gateway.payment(id: paymentID)
        guard disputedPayment.status == .disputed,
              disputedPayment.buyer == buyer,
              disputedPayment.claimType == claimType else {
            throw BuyerWorkflowError.paymentMismatch
        }

        await onProgress(.confirmed(paymentID: paymentID, transactionHash: transactionHash))
        return DisputeResult(
            payment: disputedPayment,
            uploadedEvidence: uploaded,
            transactionHash: transactionHash
        )
    }
}
