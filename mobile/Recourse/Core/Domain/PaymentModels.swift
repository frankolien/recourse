import Foundation

enum PaymentStatus: UInt8, Codable, Hashable, Sendable {
    case none = 0
    case paid = 1
    case disputed = 2
    case settled = 3
}

enum ClaimType: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case notDelivered = 0
    case damaged = 1
    case notAsDescribed = 2
    case wrongItem = 3
    case other = 4
}

enum EvidenceKind: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case photo = 1
    case description = 2
    case trackingReference = 4
    case video = 8
}

struct PolicyRecord: Codable, Hashable, Sendable {
    let id: UInt64
    let merchant: EthereumAddress
    let disputeWindow: UInt64
    let policyHash: ChainHash
}

struct PaymentRecord: Codable, Hashable, Sendable {
    let id: UInt64
    let buyer: EthereumAddress
    let merchant: EthereumAddress
    let beneficiary: EthereumAddress
    let policyID: UInt64
    let amount: USDCAmount
    let paidAt: UInt64
    let filedAt: UInt64
    let claimType: ClaimType?
    let evidenceMask: UInt16
    let attestationType: UInt8
    let attestationValue: UInt8
    let verdictBPS: UInt16
    let status: PaymentStatus
}

struct VerdictPreview: Codable, Hashable, Sendable {
    let refundBPS: UInt16
    let requiresReturn: Bool
    let ruleIndex: UInt8
    let matched: Bool
    let verdictHash: ChainHash

    func refundAmount(for paymentAmount: USDCAmount) -> USDCAmount {
        let basisPoints = UInt64(refundBPS)
        let quotient = paymentAmount.baseUnits / 10_000
        let remainder = paymentAmount.baseUnits % 10_000
        return USDCAmount(baseUnits: quotient * basisPoints + remainder * basisPoints / 10_000)
    }
}

struct EvidenceDraft: Hashable, Sendable {
    let kind: EvidenceKind
    let content: Data

    init(kind: EvidenceKind, content: Data) throws {
        guard !content.isEmpty else { throw BuyerWorkflowError.emptyEvidence }
        self.kind = kind
        self.content = content
    }
}

struct UploadedEvidence: Codable, Hashable, Sendable {
    let kind: EvidenceKind
    let hash: ChainHash
}
