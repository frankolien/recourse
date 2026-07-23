import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let configuration: AppConfiguration
    let router: AppRouter
    let accountSession: AccountSession
    let buyerSigner: any BuyerSigner
    let paymentStore: BuyerPaymentStore

    init(
        configuration: AppConfiguration,
        router: AppRouter = AppRouter(),
        accountSession: AccountSession? = nil,
        buyerSigner: (any BuyerSigner)? = nil,
        paymentStore: BuyerPaymentStore? = nil
    ) {
        self.configuration = configuration
        self.router = router
        self.buyerSigner = buyerSigner ?? TestnetLocalSigner()
        self.paymentStore = paymentStore ?? BuyerPaymentStore()
        self.accountSession = accountSession ?? AccountSession(
            api: AccountAPIClient(baseURL: configuration.apiURL)
        )
    }

    func makeContractGateway() throws -> any ContractGateway {
        try ArcContractGateway.live(
            configuration: configuration,
            signer: buyerSigner
        )
    }

    func makeEvidenceRepository() -> any EvidenceRepository {
        EvidenceAPIClient(
            baseURL: configuration.apiURL,
            chainID: configuration.chainID,
            signer: buyerSigner
        )
    }

    static func live() -> AppEnvironment {
        AppEnvironment(configuration: .live)
    }
}

@MainActor
@Observable
final class BuyerPaymentStore {
    private struct StoredPayment: Codable {
        let id: UInt64
        let merchantAddress: String
        let policyID: UInt64
        let amountBaseUnits: UInt64
        let paidAt: UInt64
        let orderReference: String
        var state: String?
    }

    private let defaults: UserDefaults
    private let storageKey = "recourse.buyer.payments"
    private(set) var payments: [DemoPayment] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    func record(payment: PaymentRecord, request: PaymentRequest) {
        var stored = storedPayments
        let entry = StoredPayment(
            id: payment.id,
            merchantAddress: payment.merchant.value,
            policyID: payment.policyID,
            amountBaseUnits: payment.amount.baseUnits,
            paidAt: payment.paidAt,
            orderReference: request.orderReference.value,
            state: DemoPaymentState.protected.rawValue
        )
        stored.removeAll { $0.id == payment.id }
        stored.insert(entry, at: 0)
        save(stored)
    }

    func payment(id: UInt64) -> DemoPayment? {
        payments.first { $0.id == id }
    }

    func markDisputed(paymentID: UInt64) {
        var stored = storedPayments
        guard let index = stored.firstIndex(where: { $0.id == paymentID }) else { return }
        stored[index].state = DemoPaymentState.underReview.rawValue
        save(stored)
    }

    private var storedPayments: [StoredPayment] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([StoredPayment].self, from: data)) ?? []
    }

    private func restore() {
        payments = storedPayments.map(displayPayment)
    }

    private func save(_ stored: [StoredPayment]) {
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
        payments = stored.map(displayPayment)
    }

    private func displayPayment(_ stored: StoredPayment) -> DemoPayment {
        let cloudCompute = DemoCatalog.payment(id: 281)
        let paidAt = Date(timeIntervalSince1970: TimeInterval(stored.paidAt))
        return DemoPayment(
            id: stored.id,
            merchant: cloudCompute.merchant,
            item: cloudCompute.item,
            merchantSymbol: cloudCompute.merchantSymbol,
            merchantImageURL: cloudCompute.merchantImageURL,
            amount: USDCAmount(baseUnits: stored.amountBaseUnits),
            date: paidAt,
            state: DemoPaymentState(rawValue: stored.state ?? "") ?? .protected,
            policyName: "Policy #\(stored.policyID)",
            protectionEnds: paidAt.addingTimeInterval(14 * 24 * 60 * 60),
            progress: 0,
            orderReference: shortReference(stored.orderReference)
        )
    }

    private func shortReference(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }
}

#if DEBUG
extension AppEnvironment {
    static func preview() -> AppEnvironment {
        AppEnvironment(
            configuration: .live,
            accountSession: .preview()
        )
    }
}
#endif
