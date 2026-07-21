import Foundation

enum CheckoutPlan: Equatable, Sendable {
    case approveThenPay(approvalAmount: USDCAmount)
    case payDirectly
}

enum CheckoutProgress: Equatable, Sendable {
    case validating
    case loadingPolicy
    case checkingFunds
    case approvalSubmitted(ChainHash)
    case approvalConfirmed(ChainHash)
    case paymentSubmitted(ChainHash)
    case paymentConfirmed(paymentID: UInt64, transactionHash: ChainHash)
}

struct CheckoutResult: Equatable, Sendable {
    let payment: PaymentRecord
    let transactionHash: ChainHash
}

struct CheckoutPlanner: Sendable {
    func plan(
        request: PaymentRequest,
        policy: PolicyRecord,
        balance: USDCAmount,
        allowance: USDCAmount,
        configuration: AppConfiguration
    ) throws -> CheckoutPlan {
        try request.validate(against: configuration)
        guard policy.id == request.policyID,
              policy.merchant.value.lowercased() == request.merchant.value.lowercased() else {
            throw BuyerWorkflowError.merchantMismatch
        }
        guard balance >= request.amount else {
            throw BuyerWorkflowError.insufficientBalance(required: request.amount, available: balance)
        }
        guard allowance < request.amount else { return .payDirectly }
        return .approveThenPay(approvalAmount: request.amount)
    }
}

struct CheckoutWorkflow: Sendable {
    private let gateway: any ContractGateway
    private let configuration: AppConfiguration
    private let planner = CheckoutPlanner()

    init(gateway: any ContractGateway, configuration: AppConfiguration) {
        self.gateway = gateway
        self.configuration = configuration
    }

    func execute(
        request: PaymentRequest,
        buyer: EthereumAddress,
        onProgress: @escaping @Sendable (CheckoutProgress) async -> Void = { _ in }
    ) async throws -> CheckoutResult {
        await onProgress(.validating)
        try request.validate(against: configuration)

        await onProgress(.loadingPolicy)
        let policy = try await gateway.policy(id: request.policyID)

        await onProgress(.checkingFunds)
        async let balance = gateway.usdcBalance(of: buyer)
        async let allowance = gateway.allowance(owner: buyer, spender: configuration.escrowAddress)
        let (currentBalance, currentAllowance) = try await (balance, allowance)
        let plan = try planner.plan(
            request: request,
            policy: policy,
            balance: currentBalance,
            allowance: currentAllowance,
            configuration: configuration
        )

        if case .approveThenPay(let approvalAmount) = plan {
            let approvalHash = try await gateway.approveUSDC(amount: approvalAmount)
            await onProgress(.approvalSubmitted(approvalHash))
            let approvalReceipt = try await gateway.waitForReceipt(transactionHash: approvalHash)
            guard approvalReceipt.outcome == .confirmed else {
                throw BuyerWorkflowError.transactionReverted(approvalHash)
            }
            await onProgress(.approvalConfirmed(approvalHash))
        }

        let paymentHash = try await gateway.pay(request)
        await onProgress(.paymentSubmitted(paymentHash))
        let paymentReceipt = try await gateway.waitForReceipt(transactionHash: paymentHash)
        guard paymentReceipt.outcome == .confirmed else {
            throw BuyerWorkflowError.transactionReverted(paymentHash)
        }
        guard let paymentID = paymentReceipt.paymentID else {
            throw BuyerWorkflowError.missingPaymentID(paymentHash)
        }

        let payment = try await gateway.payment(id: paymentID)
        guard payment.buyer == buyer,
              payment.merchant == request.merchant,
              payment.policyID == request.policyID,
              payment.amount == request.amount,
              payment.status == .paid else {
            throw BuyerWorkflowError.paymentMismatch
        }

        await onProgress(.paymentConfirmed(paymentID: paymentID, transactionHash: paymentHash))
        return CheckoutResult(payment: payment, transactionHash: paymentHash)
    }
}
