import Foundation

enum VerdictReadiness: Equatable, Sendable {
    case awaitingAttestation(until: UInt64)
    case ready(VerdictPreview)
    case settled(VerdictPreview)
}

struct VerdictResolution: Equatable, Sendable {
    let payment: PaymentRecord
    let verdict: VerdictPreview
    let transactionHash: ChainHash
}

struct VerdictWorkflow: Sendable {
    private let gateway: any ContractGateway
    private let timeProvider: any UnixTimeProvider

    init(gateway: any ContractGateway, timeProvider: any UnixTimeProvider) {
        self.gateway = gateway
        self.timeProvider = timeProvider
    }

    func inspect(paymentID: UInt64) async throws -> VerdictReadiness {
        let payment = try await gateway.payment(id: paymentID)
        guard payment.status == .disputed || payment.status == .settled else {
            throw BuyerWorkflowError.paymentNotDisputed
        }

        let preview = try await gateway.previewVerdict(paymentID: paymentID)
        if payment.status == .settled { return .settled(preview) }
        if payment.attestationType != 0 { return .ready(preview) }

        let delay = try await gateway.resolveDelay()
        let resolvesAt = payment.filedAt.addingReportingOverflow(delay)
        guard !resolvesAt.overflow, timeProvider.now() >= resolvesAt.partialValue else {
            return .awaitingAttestation(until: resolvesAt.partialValue)
        }
        return .ready(preview)
    }

    func resolve(paymentID: UInt64) async throws -> VerdictResolution {
        let readiness = try await inspect(paymentID: paymentID)
        guard case .ready = readiness else {
            if case .awaitingAttestation(let until) = readiness {
                throw BuyerWorkflowError.awaitingAttestation(until: until)
            }
            throw BuyerWorkflowError.paymentNotDisputed
        }

        let transactionHash = try await gateway.resolve(paymentID: paymentID)
        let receipt = try await gateway.waitForReceipt(transactionHash: transactionHash)
        guard receipt.outcome == .confirmed else {
            throw BuyerWorkflowError.transactionReverted(transactionHash)
        }

        let payment = try await gateway.payment(id: paymentID)
        guard payment.status == .settled else {
            throw BuyerWorkflowError.settlementNotConfirmed
        }
        let verdict = try await gateway.previewVerdict(paymentID: paymentID)
        return VerdictResolution(payment: payment, verdict: verdict, transactionHash: transactionHash)
    }
}
