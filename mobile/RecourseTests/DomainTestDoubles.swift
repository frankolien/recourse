import Foundation
@testable import Recourse

enum DomainFixture {
    static let buyer = EthereumAddress(trusted: "0x1111111111111111111111111111111111111111")
    static let merchant = EthereumAddress(trusted: "0x2222222222222222222222222222222222222222")
    static let beneficiary = merchant
    static let other = EthereumAddress(trusted: "0x3333333333333333333333333333333333333333")
    static let orderReference = ChainHash(trusted: "0x" + String(repeating: "ab", count: 32))
    static let policyHash = ChainHash(trusted: "0x" + String(repeating: "cd", count: 32))
    static let verdictHash = ChainHash(trusted: "0x" + String(repeating: "ef", count: 32))
    static let approvalHash = ChainHash(trusted: "0x" + String(repeating: "01", count: 32))
    static let paymentHash = ChainHash(trusted: "0x" + String(repeating: "02", count: 32))
    static let disputeHash = ChainHash(trusted: "0x" + String(repeating: "03", count: 32))
    static let resolveHash = ChainHash(trusted: "0x" + String(repeating: "04", count: 32))

    static let policy = PolicyRecord(
        id: 3,
        merchant: merchant,
        disputeWindow: 1_000,
        policyHash: policyHash
    )

    static let request = PaymentRequest(
        version: 1,
        chainID: Deployment.chainID,
        escrow: EthereumAddress(trusted: Deployment.escrow),
        policyID: policy.id,
        merchant: merchant,
        amount: USDCAmount(baseUnits: 25_000_000),
        orderReference: orderReference
    )

    static func payment(
        status: PaymentStatus = .paid,
        buyer: EthereumAddress = buyer,
        paidAt: UInt64 = 10_000,
        filedAt: UInt64 = 0,
        claimType: ClaimType? = nil,
        attestationType: UInt8 = 0,
        verdictBPS: UInt16 = 0
    ) -> PaymentRecord {
        PaymentRecord(
            id: 9,
            buyer: buyer,
            merchant: merchant,
            beneficiary: beneficiary,
            policyID: policy.id,
            amount: request.amount,
            paidAt: paidAt,
            filedAt: filedAt,
            claimType: claimType,
            evidenceMask: 0,
            attestationType: attestationType,
            attestationValue: 0,
            verdictBPS: verdictBPS,
            status: status
        )
    }

    static let verdict = VerdictPreview(
        refundBPS: 10_000,
        requiresReturn: false,
        ruleIndex: 0,
        matched: true,
        verdictHash: verdictHash
    )
}

actor FakeContractGateway: ContractGateway {
    enum Call: Equatable {
        case approve(USDCAmount)
        case pay
        case fileDispute(ClaimType, [UploadedEvidence])
        case resolve
    }

    var balance: USDCAmount
    var currentAllowance: USDCAmount
    var policyRecord: PolicyRecord
    var paymentRecord: PaymentRecord
    var verdict: VerdictPreview
    var delay: UInt64
    var approvalOutcome: ChainReceipt.Outcome = .confirmed
    var paymentOutcome: ChainReceipt.Outcome = .confirmed
    var disputeOutcome: ChainReceipt.Outcome = .confirmed
    var resolveOutcome: ChainReceipt.Outcome = .confirmed
    private(set) var calls: [Call] = []

    init(
        balance: USDCAmount = USDCAmount(baseUnits: 100_000_000),
        allowance: USDCAmount = USDCAmount(baseUnits: 0),
        policy: PolicyRecord = DomainFixture.policy,
        payment: PaymentRecord = DomainFixture.payment(),
        verdict: VerdictPreview = DomainFixture.verdict,
        delay: UInt64 = 60
    ) {
        self.balance = balance
        currentAllowance = allowance
        policyRecord = policy
        paymentRecord = payment
        self.verdict = verdict
        self.delay = delay
    }

    func usdcBalance(of owner: EthereumAddress) async throws -> USDCAmount { balance }
    func allowance(owner: EthereumAddress, spender: EthereumAddress) async throws -> USDCAmount {
        currentAllowance
    }
    func policy(id: UInt64) async throws -> PolicyRecord { policyRecord }
    func payment(id: UInt64) async throws -> PaymentRecord { paymentRecord }
    func previewVerdict(paymentID: UInt64) async throws -> VerdictPreview { verdict }
    func resolveDelay() async throws -> UInt64 { delay }

    func approveUSDC(amount: USDCAmount) async throws -> ChainHash {
        calls.append(.approve(amount))
        currentAllowance = amount
        return DomainFixture.approvalHash
    }

    func pay(_ request: PaymentRequest) async throws -> ChainHash {
        calls.append(.pay)
        return DomainFixture.paymentHash
    }

    func fileDispute(
        paymentID: UInt64,
        claimType: ClaimType,
        evidence: [UploadedEvidence]
    ) async throws -> ChainHash {
        calls.append(.fileDispute(claimType, evidence))
        paymentRecord = paymentRecord.replacing(
            status: .disputed,
            filedAt: paymentRecord.paidAt + 10,
            claimType: claimType
        )
        return DomainFixture.disputeHash
    }

    func resolve(paymentID: UInt64) async throws -> ChainHash {
        calls.append(.resolve)
        paymentRecord = paymentRecord.replacing(status: .settled, verdictBPS: verdict.refundBPS)
        return DomainFixture.resolveHash
    }

    func waitForReceipt(transactionHash: ChainHash) async throws -> ChainReceipt {
        switch transactionHash {
        case DomainFixture.approvalHash:
            ChainReceipt(transactionHash: transactionHash, outcome: approvalOutcome, paymentID: nil)
        case DomainFixture.paymentHash:
            ChainReceipt(transactionHash: transactionHash, outcome: paymentOutcome, paymentID: 9)
        case DomainFixture.disputeHash:
            ChainReceipt(transactionHash: transactionHash, outcome: disputeOutcome, paymentID: nil)
        default:
            ChainReceipt(transactionHash: transactionHash, outcome: resolveOutcome, paymentID: nil)
        }
    }

    func recordedCalls() -> [Call] { calls }
}

actor FakeEvidenceRepository: EvidenceRepository {
    private(set) var uploadedKinds: [EvidenceKind] = []
    private(set) var uploadedPaymentIDs: [UInt64] = []
    private(set) var publishedManifests: [[UploadedEvidence]] = []

    func upload(_ evidence: EvidenceDraft, paymentID: UInt64) async throws -> UploadedEvidence {
        uploadedKinds.append(evidence.kind)
        uploadedPaymentIDs.append(paymentID)
        let byte = String(format: "%02x", uploadedKinds.count + 16)
        return UploadedEvidence(
            kind: evidence.kind,
            hash: ChainHash(trusted: "0x" + String(repeating: byte, count: 32))
        )
    }

    func publishManifest(
        paymentID: UInt64,
        evidence: [UploadedEvidence]
    ) async throws -> EvidenceManifestReceipt {
        publishedManifests.append(evidence)
        let root = ChainHash(trusted: "0x" + String(repeating: "44", count: 32))
        return EvidenceManifestReceipt(
            paymentID: paymentID,
            matches: true,
            computedRoot: root,
            onchainRoot: root
        )
    }

    func kinds() -> [EvidenceKind] { uploadedKinds }
    func paymentIDs() -> [UInt64] { uploadedPaymentIDs }
    func manifests() -> [[UploadedEvidence]] { publishedManifests }
}

struct FixedTimeProvider: UnixTimeProvider {
    let timestamp: UInt64
    func now() -> UInt64 { timestamp }
}

private extension PaymentRecord {
    func replacing(
        status: PaymentStatus,
        filedAt: UInt64? = nil,
        claimType: ClaimType? = nil,
        verdictBPS: UInt16? = nil
    ) -> PaymentRecord {
        PaymentRecord(
            id: id,
            buyer: buyer,
            merchant: merchant,
            beneficiary: beneficiary,
            policyID: policyID,
            amount: amount,
            paidAt: paidAt,
            filedAt: filedAt ?? self.filedAt,
            claimType: claimType ?? self.claimType,
            evidenceMask: evidenceMask,
            attestationType: attestationType,
            attestationValue: attestationValue,
            verdictBPS: verdictBPS ?? self.verdictBPS,
            status: status
        )
    }
}
