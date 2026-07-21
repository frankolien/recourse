import Foundation

struct ChainReceipt: Hashable, Sendable {
    enum Outcome: Hashable, Sendable {
        case confirmed
        case reverted
    }

    let transactionHash: ChainHash
    let outcome: Outcome
    let paymentID: UInt64?
}

protocol ContractReading: Sendable {
    func usdcBalance(of owner: EthereumAddress) async throws -> USDCAmount
    func allowance(owner: EthereumAddress, spender: EthereumAddress) async throws -> USDCAmount
    func policy(id: UInt64) async throws -> PolicyRecord
    func payment(id: UInt64) async throws -> PaymentRecord
    func previewVerdict(paymentID: UInt64) async throws -> VerdictPreview
    func resolveDelay() async throws -> UInt64
}

protocol ContractWriting: Sendable {
    func approveUSDC(amount: USDCAmount) async throws -> ChainHash
    func pay(_ request: PaymentRequest) async throws -> ChainHash
    func fileDispute(
        paymentID: UInt64,
        claimType: ClaimType,
        evidence: [UploadedEvidence]
    ) async throws -> ChainHash
    func resolve(paymentID: UInt64) async throws -> ChainHash
    func waitForReceipt(transactionHash: ChainHash) async throws -> ChainReceipt
}

protocol ContractGateway: ContractReading, ContractWriting {}

protocol EvidenceRepository: Sendable {
    func upload(_ evidence: EvidenceDraft) async throws -> UploadedEvidence
}

protocol BuyerPaymentRepository: Sendable {
    func payments(for buyer: EthereumAddress) async throws -> [PaymentRecord]
}

protocol UnixTimeProvider: Sendable {
    func now() -> UInt64
}

struct SystemUnixTimeProvider: UnixTimeProvider {
    func now() -> UInt64 {
        UInt64(Date().timeIntervalSince1970)
    }
}
