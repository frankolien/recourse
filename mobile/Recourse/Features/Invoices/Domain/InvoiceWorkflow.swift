import Foundation

enum InvoiceError: Error, Equatable {
    case zeroAmount
    case selfInvoice
    case missingMemo
    case notYours
    case alreadyAnswered
    case expired
    /// Signing would promise more than the wallet holds once existing promises are
    /// counted. Refused here rather than at collection time, because a signature that
    /// cannot be honoured is worse than a refusal: the issuer believes they are paid.
    case overcommitted(available: USDCAmount)
    case notSigned
    case transactionReverted(ChainHash)
}

/// How long an invoice stays payable unless the issuer says otherwise.
enum InvoiceTerms: String, CaseIterable, Identifiable, Sendable {
    case onReceipt
    case week
    case fortnight
    case month

    var id: String { rawValue }

    var seconds: UInt64 {
        switch self {
        case .onReceipt: 3 * 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .fortnight: 14 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .onReceipt: "On receipt"
        case .week: "Net 7"
        case .fortnight: "Net 14"
        case .month: "Net 30"
        }
    }

    var detail: String {
        switch self {
        case .onReceipt: "Payable now, expires in 3 days"
        case .week: "Payable within 7 days"
        case .fortnight: "Payable within 14 days"
        case .month: "Payable within 30 days"
        }
    }
}

/// Issuing, answering, collecting and withdrawing an invoice.
///
/// An invoice is a request for a cheque, so almost none of this is new machinery. The
/// issuer fixes the terms and picks the nonce; the payer signs an EIP-3009
/// authorization over exactly those terms; the issuer submits it. What the issuer
/// cannot do is alter anything after the fact, because every term is inside what was
/// signed.
struct InvoiceWorkflow: Sendable {
    private let gateway: any ContractGateway
    private let signer: any BuyerSigner
    private let api: any InvoiceAPI
    private let configuration: AppConfiguration
    private let clock: @Sendable () -> Date

    init(
        gateway: any ContractGateway,
        signer: any BuyerSigner,
        api: any InvoiceAPI,
        configuration: AppConfiguration,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.signer = signer
        self.api = api
        self.configuration = configuration
        self.clock = clock
    }

    /// Ask someone for money. Costs nothing and touches no chain: an invoice is a
    /// request, and until it is answered there is no authorization in existence.
    func issue(
        to payer: EthereumAddress,
        amount: USDCAmount,
        terms: InvoiceTerms,
        memo: String,
        accessToken: String
    ) async throws -> StoredInvoice {
        guard amount.baseUnits > 0 else { throw InvoiceError.zeroAmount }
        guard !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvoiceError.missingMemo
        }
        let issuer = try await signer.address()
        guard payer.value.lowercased() != issuer.value.lowercased() else {
            throw InvoiceError.selfInvoice
        }

        let due = UInt64(clock().timeIntervalSince1970) + terms.seconds
        return try await api.issue(
            InvoiceDraft(
                issuer: issuer,
                payer: payer,
                amount: amount,
                due: due,
                // Chosen by the issuer, which is what fixes the terms: the payer signs
                // over this nonce or does not pay, and cannot substitute another.
                nonce: Cheque.randomNonce(),
                memo: memo
            ),
            accessToken: accessToken
        )
    }

    /// Answer an invoice by signing its authorization.
    ///
    /// `committed` is what this wallet already owes on live cheques, passed in so the
    /// screen and the check agree. Signing an invoice is another promise against the
    /// same balance, and the app counts it the same way.
    func pay(
        _ invoice: StoredInvoice,
        committed: USDCAmount,
        accessToken: String
    ) async throws -> StoredInvoice {
        guard let authorization = invoice.authorization else { throw InvoiceError.notYours }
        let me = try await signer.address()
        guard authorization.from.value.lowercased() == me.value.lowercased() else {
            throw InvoiceError.notYours
        }
        guard !invoice.isSigned, !invoice.isCancelled else { throw InvoiceError.alreadyAnswered }
        guard invoice.dueAt > clock() else { throw InvoiceError.expired }

        let balance = try await gateway.usdcBalance(of: me)
        let available = balance.baseUnits > committed.baseUnits
            ? balance.baseUnits - committed.baseUnits
            : 0
        guard invoice.amountBaseUnits <= available else {
            throw InvoiceError.overcommitted(available: USDCAmount(baseUnits: available))
        }

        let signature = try await signer.signEIP712(
            ChequeAuthorization.typedData(
                for: authorization,
                token: configuration.usdcAddress,
                chainID: Int(configuration.chainID)
            )
        )
        return try await api.sign(
            invoiceID: invoice.invoiceId,
            signature: signature,
            accessToken: accessToken
        )
    }

    /// Submit an answered invoice and take the money.
    ///
    /// The issuer pays the gas here, which is the right way round: it is their money
    /// being collected, and it means the payer's side of an invoice costs nothing.
    func collect(_ invoice: StoredInvoice) async throws -> ChainHash {
        guard let authorization = invoice.authorization,
              let signature = invoice.signatureBytes else { throw InvoiceError.notSigned }
        let me = try await signer.address()
        guard authorization.to.value.lowercased() == me.value.lowercased() else {
            throw InvoiceError.notYours
        }
        guard invoice.dueAt > clock() else { throw InvoiceError.expired }

        let spent = try await gateway.authorizationState(
            authorizer: authorization.from,
            nonce: authorization.nonce
        )
        guard !spent else { throw InvoiceError.alreadyAnswered }

        let hash = try await gateway.cashCheque(authorization, signature: signature)
        let receipt = try await gateway.waitForReceipt(transactionHash: hash)
        guard receipt.outcome == .confirmed else {
            throw InvoiceError.transactionReverted(hash)
        }
        return hash
    }

    /// Withdraw a request nobody has answered.
    func cancel(_ invoice: StoredInvoice, accessToken: String) async throws -> StoredInvoice {
        guard !invoice.isSigned else { throw InvoiceError.alreadyAnswered }
        return try await api.cancel(invoiceID: invoice.invoiceId, accessToken: accessToken)
    }
}
