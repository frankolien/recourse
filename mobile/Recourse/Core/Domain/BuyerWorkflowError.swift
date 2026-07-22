import Foundation

enum BuyerWorkflowError: Error, Equatable {
    case merchantMismatch
    case insufficientBalance(required: USDCAmount, available: USDCAmount)
    case transactionReverted(ChainHash)
    case missingPaymentID(ChainHash)
    case paymentMismatch
    case notBuyer
    case paymentNotOpen
    case paymentNotDisputed
    case disputeWindowClosed
    case emptyEvidence
    case evidenceManifestMismatch
    case awaitingAttestation(until: UInt64)
    case settlementNotConfirmed
}
