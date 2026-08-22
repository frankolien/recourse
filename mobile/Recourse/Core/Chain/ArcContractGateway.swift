import Foundation
@preconcurrency import BigInt

struct ArcContractGateway: ContractGateway {
    private let reader: ArcContractReader
    private let writer: ArcContractWriter

    init(reader: ArcContractReader, writer: ArcContractWriter) {
        self.reader = reader
        self.writer = writer
    }

    static func live(
        configuration: AppConfiguration = .live,
        signer: any BuyerSigner = TestnetLocalSigner()
    ) throws -> ArcContractGateway {
        let transport = HTTPArcRPCTransport(rpcURL: configuration.rpcURL)
        return try ArcContractGateway(
            reader: ArcContractReader(configuration: configuration, transport: transport),
            writer: ArcContractWriter(
                configuration: configuration,
                signer: signer,
                transport: transport
            )
        )
    }

    func usdcBalance(of owner: EthereumAddress) async throws -> USDCAmount {
        try await reader.usdcBalance(of: owner)
    }

    func allowance(owner: EthereumAddress, spender: EthereumAddress) async throws -> USDCAmount {
        try await reader.allowance(owner: owner, spender: spender)
    }

    func policy(id: UInt64) async throws -> PolicyRecord {
        try await reader.policy(id: id)
    }

    func payment(id: UInt64) async throws -> PaymentRecord {
        try await reader.payment(id: id)
    }

    func previewVerdict(paymentID: UInt64) async throws -> VerdictPreview {
        try await reader.previewVerdict(paymentID: paymentID)
    }

    func resolveDelay() async throws -> UInt64 {
        try await reader.resolveDelay()
    }

    func vaultState(of owner: EthereumAddress) async throws -> VaultState {
        try await reader.vaultState(of: owner)
    }

    func fxAmountOut(amountIn: USDCAmount) async throws -> BigUInt {
        try await reader.fxAmountOut(amountIn: amountIn)
    }

    func fxReserves() async throws -> FXReserves {
        try await reader.fxReserves()
    }

    func approveUSDC(amount: USDCAmount) async throws -> ChainHash {
        try await writer.approveUSDC(amount: amount)
    }

    func transferUSDC(to recipient: EthereumAddress, amount: USDCAmount) async throws -> ChainHash {
        try await writer.transferUSDC(to: recipient, amount: amount)
    }

    func registerStarterPolicy() async throws -> ChainHash {
        try await writer.registerStarterPolicy()
    }

    func pay(_ request: PaymentRequest) async throws -> ChainHash {
        try await writer.pay(request)
    }

    func fileDispute(
        paymentID: UInt64,
        claimType: ClaimType,
        evidence: [UploadedEvidence]
    ) async throws -> ChainHash {
        try await writer.fileDispute(
            paymentID: paymentID,
            claimType: claimType,
            evidence: evidence
        )
    }

    func resolve(paymentID: UInt64) async throws -> ChainHash {
        try await writer.resolve(paymentID: paymentID)
    }

    func approveVaultUSDC(amount: USDCAmount) async throws -> ChainHash {
        try await writer.approveVaultUSDC(amount: amount)
    }

    func vaultDeposit(amount: USDCAmount) async throws -> ChainHash {
        try await writer.vaultDeposit(amount: amount)
    }

    func vaultWithdraw(shares: UInt64) async throws -> ChainHash {
        try await writer.vaultWithdraw(shares: shares)
    }

    func waitForReceipt(transactionHash: ChainHash) async throws -> ChainReceipt {
        try await writer.waitForReceipt(transactionHash: transactionHash)
    }
}
