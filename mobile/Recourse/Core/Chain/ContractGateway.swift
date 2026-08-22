import Foundation
@preconcurrency import BigInt

struct ChainReceipt: Hashable, Sendable {
    enum Outcome: Hashable, Sendable {
        case confirmed
        case reverted
    }

    let transactionHash: ChainHash
    let outcome: Outcome
    let paymentID: UInt64?
}

// Live LP snapshot of the settlement vault. Share price and position value are
// display math; the contract's own conversion is what moves funds.
struct VaultState: Hashable, Sendable {
    let totalAssets: USDCAmount
    let totalShares: UInt64
    let outstanding: USDCAmount
    let myShares: UInt64

    var sharePrice: Double {
        guard totalShares > 0 else { return 1 }
        return Double(totalAssets.baseUnits) / Double(totalShares)
    }

    var myValue: USDCAmount {
        USDCAmount(baseUnits: UInt64(Double(myShares) * sharePrice))
    }

    // Shares carried by an assets figure, rounded down so a withdraw can never
    // ask for more than the position holds.
    func shares(for assets: USDCAmount) -> UInt64 {
        guard sharePrice > 0 else { return 0 }
        return min(myShares, UInt64(Double(assets.baseUnits) / sharePrice))
    }
}

protocol ContractReading: Sendable {
    func usdcBalance(of owner: EthereumAddress) async throws -> USDCAmount
    func allowance(owner: EthereumAddress, spender: EthereumAddress) async throws -> USDCAmount
    func policy(id: UInt64) async throws -> PolicyRecord
    func payment(id: UInt64) async throws -> PaymentRecord
    func previewVerdict(paymentID: UInt64) async throws -> VerdictPreview
    func resolveDelay() async throws -> UInt64
    func vaultState(of owner: EthereumAddress) async throws -> VaultState
    /// Output the FX venue would pay for `amountIn` of USDC, in EURC base units.
    /// Quoted through the router rather than derived from reserves, so the number
    /// shown and the number filled come from one curve, one fee, one rounding.
    func fxAmountOut(amountIn: USDCAmount) async throws -> BigUInt
}

protocol ContractWriting: Sendable {
    func approveUSDC(amount: USDCAmount) async throws -> ChainHash
    // Direct USDC transfer, deliberately outside the escrow: no policy, no protection.
    // The product's protected path stays pay(); this exists for person-to-person sends.
    func transferUSDC(to recipient: EthereumAddress, amount: USDCAmount) async throws -> ChainHash
    func registerStarterPolicy() async throws -> ChainHash
    func pay(_ request: PaymentRequest) async throws -> ChainHash
    func fileDispute(
        paymentID: UInt64,
        claimType: ClaimType,
        evidence: [UploadedEvidence]
    ) async throws -> ChainHash
    func resolve(paymentID: UInt64) async throws -> ChainHash
    func approveVaultUSDC(amount: USDCAmount) async throws -> ChainHash
    func vaultDeposit(amount: USDCAmount) async throws -> ChainHash
    func vaultWithdraw(shares: UInt64) async throws -> ChainHash
    func waitForReceipt(transactionHash: ChainHash) async throws -> ChainReceipt
}

protocol ContractGateway: ContractReading, ContractWriting {}

protocol EvidenceRepository: Sendable {
    func upload(_ evidence: EvidenceDraft, paymentID: UInt64) async throws -> UploadedEvidence
    func publishManifest(
        paymentID: UInt64,
        evidence: [UploadedEvidence]
    ) async throws -> EvidenceManifestReceipt
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
