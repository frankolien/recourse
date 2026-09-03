import Foundation

enum ChequeError: Error, Equatable {
    case zeroAmount
    case selfCheque
    /// The writer's own balance would not cover this cheque plus everything they have
    /// already written and not yet had cashed.
    case overcommitted(available: USDCAmount)
    case expiryInThePast
    case notYours
    case alreadySettled
    case transactionReverted(ChainHash)
}

/// How long a cheque stays cashable unless the writer says otherwise.
enum ChequeValidity: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case quarter

    var id: String { rawValue }

    var seconds: UInt64 {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        case .quarter: 90 * 24 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .day: "24 hours"
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        }
    }

    var shortLabel: String {
        switch self {
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        case .quarter: "90d"
        }
    }
}

/// Writing, cashing and voiding a cheque.
///
/// Writing costs nothing and touches no chain: it is a signature and an upload. That is
/// the feature, and also the hazard, because a signature is a promise made against a
/// balance nothing is holding. So the one check that cannot be skipped here is the
/// commitment check, and it runs against what is already promised rather than against
/// the raw balance.
struct ChequeWorkflow: Sendable {
    private let gateway: any ContractGateway
    private let signer: any BuyerSigner
    private let api: any ChequeAPI
    private let configuration: AppConfiguration
    private let clock: @Sendable () -> Date

    init(
        gateway: any ContractGateway,
        signer: any BuyerSigner,
        api: any ChequeAPI,
        configuration: AppConfiguration,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.signer = signer
        self.api = api
        self.configuration = configuration
        self.clock = clock
    }

    /// Sign a cheque and hand it to the postbox.
    ///
    /// `committed` is what the caller already knows this writer owes on other live
    /// cheques. Passed in rather than recomputed so this stays one round trip and the
    /// screen and the check agree on the same number.
    func write(
        to recipient: EthereumAddress,
        amount: USDCAmount,
        validity: ChequeValidity,
        memo: String?,
        committed: USDCAmount,
        accessToken: String
    ) async throws -> StoredCheque {
        guard amount.baseUnits > 0 else { throw ChequeError.zeroAmount }
        let writer = try await signer.address()
        guard recipient.value.lowercased() != writer.value.lowercased() else {
            throw ChequeError.selfCheque
        }

        let balance = try await gateway.usdcBalance(of: writer)
        let available = balance.baseUnits > committed.baseUnits
            ? balance.baseUnits - committed.baseUnits
            : 0
        guard amount.baseUnits <= available else {
            throw ChequeError.overcommitted(available: USDCAmount(baseUnits: available))
        }

        let now = UInt64(clock().timeIntervalSince1970)
        let cheque = Cheque(
            from: writer,
            to: recipient,
            amount: amount,
            // Zero, not `now`: the token requires validAfter to be strictly in the past,
            // and a writer whose clock runs a few seconds fast would otherwise sign a
            // cheque nobody can cash for a minute.
            validAfter: 0,
            validBefore: now + validity.seconds,
            nonce: Cheque.randomNonce()
        )

        let typedData = try ChequeAuthorization.typedData(
            for: cheque,
            token: configuration.usdcAddress,
            chainID: Int(configuration.chainID)
        )
        let signature = try await signer.signEIP712(typedData)

        return try await api.write(
            ChequeDraft(cheque: cheque, signature: signature, memo: memo),
            accessToken: accessToken
        )
    }

    /// Submit a cheque written to you and take the money.
    ///
    /// The chain is asked first because the alternative is paying gas to be told the
    /// cheque was already cashed, and a failed transaction is a worse answer than a
    /// sentence.
    func cash(_ stored: StoredCheque) async throws -> ChainHash {
        guard let cheque = stored.cheque else { throw ChequeError.notYours }
        let me = try await signer.address()
        guard cheque.to.value.lowercased() == me.value.lowercased() else {
            throw ChequeError.notYours
        }
        guard stored.expiresAt > clock() else { throw ChequeError.expiryInThePast }
        let spent = try await gateway.authorizationState(authorizer: cheque.from, nonce: cheque.nonce)
        guard !spent else { throw ChequeError.alreadySettled }

        let hash = try await gateway.cashCheque(cheque, signature: stored.signatureBytes)
        let receipt = try await gateway.waitForReceipt(transactionHash: hash)
        guard receipt.outcome == .confirmed else {
            throw ChequeError.transactionReverted(hash)
        }
        return hash
    }

    /// Burn a cheque's nonce so it can never be cashed.
    func void(_ stored: StoredCheque) async throws -> ChainHash {
        guard let cheque = stored.cheque else { throw ChequeError.notYours }
        let me = try await signer.address()
        guard cheque.from.value.lowercased() == me.value.lowercased() else {
            throw ChequeError.notYours
        }
        let spent = try await gateway.authorizationState(authorizer: cheque.from, nonce: cheque.nonce)
        guard !spent else { throw ChequeError.alreadySettled }

        let typedData = try ChequeAuthorization.cancellationTypedData(
            authorizer: me,
            nonce: cheque.nonce,
            token: configuration.usdcAddress,
            chainID: Int(configuration.chainID)
        )
        let signature = try await signer.signEIP712(typedData)
        let hash = try await gateway.voidCheque(nonce: cheque.nonce, cancellationSignature: signature)
        let receipt = try await gateway.waitForReceipt(transactionHash: hash)
        guard receipt.outcome == .confirmed else {
            throw ChequeError.transactionReverted(hash)
        }
        return hash
    }
}
