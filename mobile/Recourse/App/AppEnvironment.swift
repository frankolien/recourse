import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class AppEnvironment {
    let configuration: AppConfiguration
    let router: AppRouter
    let accountSession: AccountSession
    let buyerSigner: any BuyerSigner
    let paymentStore: BuyerPaymentStore
    let addressBook = AddressBookStore()

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
        self.paymentStore = paymentStore ?? BuyerPaymentStore(
            configuration: configuration,
            signer: self.buyerSigner
        )
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

    func makeOrderAPIClient() -> OrderAPIClient {
        OrderAPIClient(baseURL: configuration.apiURL)
    }

    func makeHandleAPIClient() -> any HandleAPI {
        HandleAPIClient(baseURL: configuration.apiURL)
    }

    static func live() -> AppEnvironment {
        AppEnvironment(configuration: .live)
    }
}

@MainActor
@Observable
final class BuyerPaymentStore {
    private struct IndexedPayment: Decodable, Sendable {
        let paymentId: Int64
        let buyer: String
        let merchant: String
        let policyId: Int64
        let amount: String
        let paidAt: Int64
        let filedAt: Int64
        let evidenceMask: Int32
        let status: Int32
        let refundBps: Int32?
        let orderRef: String?
    }

    private struct IndexedPolicy: Decodable, Sendable {
        let policyId: Int64
        let merchant: String
        let disputeWindow: Int64
        let policyHash: String
    }

    private enum Scope: String, Sendable {
        case buyer
        case merchant
    }

    private let configuration: AppConfiguration
    private let signer: any BuyerSigner
    private let session: URLSession
    private(set) var payments: [DemoPayment] = []
    private(set) var merchantPayments: [DemoPayment] = []
    private(set) var policies: [PolicyRecord] = []
    private(set) var balance: USDCAmount?
    private(set) var walletAddress: EthereumAddress?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    init(
        configuration: AppConfiguration = .live,
        signer: any BuyerSigner = TestnetLocalSigner(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.signer = signer
        self.session = session
    }

    // What the buyer actually bought, remembered per payment at pay time. The indexer
    // only knows chain data (addresses, amounts); the item name and product image come
    // from the order manifest this device verified before paying, so rows can show the
    // real purchase instead of a bare merchant address. Persisted across launches.
    private struct OrderContext: Codable {
        let itemName: String
        let imageHash: String?
    }

    // orderRefs that resolved to no manifest (seeded payments, foreign clients); skip
    // them for the rest of the session instead of refetching every refresh.
    private var unresolvableOrderRefs: Set<String> = []

    // The account whose data is currently held. Starts deliberately unequal to
    // any real scope so the first refresh always establishes it.
    private var loadedAccountScope: String? = "unloaded"

    // Scoped to the signed-in account: what someone bought is theirs, and two
    // accounts sharing a device must not read each other's purchase history.
    private var orderContextKey: String {
        ActiveAccount.scope.map { "recourse.buyer.orderContext.\($0)" } ?? "recourse.buyer.orderContext"
    }

    private var orderContexts: [UInt64: OrderContext] {
        get {
            guard let data = UserDefaults.standard.data(forKey: orderContextKey),
                  let decoded = try? JSONDecoder().decode([UInt64: OrderContext].self, from: data)
            else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: orderContextKey)
            }
        }
    }

    func record(payment: PaymentRecord, request: PaymentRequest, manifest: OrderManifest?) {
        if let manifest {
            var contexts = orderContexts
            contexts[payment.id] = OrderContext(
                itemName: manifest.itemName,
                imageHash: manifest.imageHash
            )
            orderContexts = contexts
        }
        let policy = policies.first { $0.id == payment.policyID }
        let display = displayPayment(
            id: payment.id,
            merchantAddress: payment.merchant.value,
            policyID: payment.policyID,
            amount: payment.amount,
            paidAt: payment.paidAt,
            filedAt: payment.filedAt,
            evidenceMask: Int32(payment.evidenceMask),
            status: Int32(payment.status.rawValue),
            refundBPS: nil,
            disputeWindow: policy?.disputeWindow ?? 0
        )
        payments.removeAll { $0.id == payment.id }
        payments.insert(display, at: 0)

        Task {
            try? await Task.sleep(for: .seconds(2))
            await refreshBuyer()
        }
    }

    func payment(id: UInt64) -> DemoPayment? {
        payments.first { $0.id == id }
            ?? merchantPayments.first { $0.id == id }
    }

    func markDisputed(paymentID: UInt64) {
        updateState(paymentID: paymentID, state: .underReview)
        Task {
            try? await Task.sleep(for: .seconds(2))
            await refreshBuyer()
        }
    }

    func refreshBuyer() async {
        await refresh(scope: .buyer)
    }

    /// Rows and a balance loaded under one account must not survive into the
    /// next. Without this the previous account's figures stay on screen until
    /// the network answers, which is long enough to read as your own.
    private func discardDataFromAnotherAccount() {
        let current = ActiveAccount.scope
        guard current != loadedAccountScope else { return }
        loadedAccountScope = current
        payments = []
        merchantPayments = []
        policies = []
        balance = nil
        walletAddress = nil
        lastUpdated = nil
        errorMessage = nil
        unresolvableOrderRefs = []
    }

    func refreshMerchant() async {
        await refresh(scope: .merchant)
    }

    private func refresh(scope: Scope) async {
        guard !isLoading else { return }
        discardDataFromAnotherAccount()
        isLoading = true
        defer { isLoading = false }

        do {
            let address = try await signer.address()
            walletAddress = address
            async let indexedPayments = fetchPayments(scope: scope, address: address)
            async let indexedPolicies = fetchPolicies()

            let (paymentRows, policyRows) = try await (
                indexedPayments,
                indexedPolicies
            )
            let policyRecords = policyRows.compactMap(policyRecord)
            policies = policyRecords
            let windows = Dictionary(
                uniqueKeysWithValues: policyRecords.map { ($0.id, $0.disputeWindow) }
            )
            // Payments this device did not pay for (or paid before contexts existed)
            // resolve their order details through the indexer's orderRef, verified by
            // rehashing the fetched manifest, before rows are built.
            await resolveOrderContexts(for: paymentRows)
            let displayPayments = paymentRows.compactMap {
                displayPayment($0, disputeWindow: windows[UInt64($0.policyId)] ?? 0)
            }

            switch scope {
            case .buyer:
                payments = displayPayments
                balance = try? await fetchBalance(address: address)
                publishProtectionSnapshot()
            case .merchant:
                merchantPayments = displayPayments
                balance = try? await fetchBalance(address: address)
            }
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = "Live Arc data is unavailable. Pull to retry."
        }
    }

    // The widget renders whatever the last refresh published; pushing a reload
    // here is what keeps the home screen number honest without giving the
    // widget its own network stack.
    private func publishProtectionSnapshot() {
        let active = payments.filter { $0.state == .protected || $0.state == .underReview }
        ProtectionSnapshot(
            protectedBaseUnits: active.reduce(into: UInt64(0)) {
                $0 = $0.addingReportingOverflow($1.amount.baseUnits).partialValue
            },
            activeCount: active.count,
            nearestDeadline: active.filter { $0.state == .protected }.map(\.protectionEnds).min(),
            updatedAt: Date()
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func resolveOrderContexts(for rows: [IndexedPayment]) async {
        var contexts = orderContexts
        var changed = false
        let api = OrderAPIClient(baseURL: configuration.apiURL)
        for row in rows {
            guard row.paymentId >= 0 else { continue }
            let id = UInt64(row.paymentId)
            guard contexts[id] == nil,
                  let ref = row.orderRef,
                  !unresolvableOrderRefs.contains(ref),
                  let refHash = try? ChainHash(ref) else { continue }
            do {
                let bytes = try await api.fetchManifestBytes(orderReference: refHash)
                let manifest = try OrderManifest.decode(verifying: bytes, orderReference: refHash)
                contexts[id] = OrderContext(
                    itemName: manifest.itemName,
                    imageHash: manifest.imageHash
                )
                changed = true
            } catch {
                unresolvableOrderRefs.insert(ref)
            }
        }
        if changed {
            orderContexts = contexts
        }
    }

    private func fetchPayments(scope: Scope, address: EthereumAddress) async throws -> [IndexedPayment] {
        var components = URLComponents(
            url: configuration.apiURL.appending(path: "api/payments"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: scope.rawValue, value: address.value),
            URLQueryItem(name: "limit", value: "100")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await decode([IndexedPayment].self, from: url)
    }

    private func fetchPolicies() async throws -> [IndexedPolicy] {
        try await decode(
            [IndexedPolicy].self,
            from: configuration.apiURL.appending(path: "api/policies")
        )
    }

    private func fetchBalance(address: EthereumAddress) async throws -> USDCAmount {
        let gateway = try ArcContractGateway.live(
            configuration: configuration,
            signer: signer
        )
        return try await gateway.usdcBalance(of: address)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from url: URL) async throws -> Value {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func policyRecord(_ policy: IndexedPolicy) -> PolicyRecord? {
        guard policy.policyId >= 0,
              policy.disputeWindow >= 0,
              let merchant = try? EthereumAddress(policy.merchant),
              let policyHash = try? ChainHash(policy.policyHash) else {
            return nil
        }
        return PolicyRecord(
            id: UInt64(policy.policyId),
            merchant: merchant,
            disputeWindow: UInt64(policy.disputeWindow),
            policyHash: policyHash
        )
    }

    private func displayPayment(
        _ payment: IndexedPayment,
        disputeWindow: UInt64
    ) -> DemoPayment? {
        guard payment.paymentId >= 0,
              payment.policyId >= 0,
              payment.paidAt >= 0,
              let amountBaseUnits = UInt64(payment.amount) else {
            return nil
        }
        return displayPayment(
            id: UInt64(payment.paymentId),
            merchantAddress: payment.merchant,
            policyID: UInt64(payment.policyId),
            amount: USDCAmount(baseUnits: amountBaseUnits),
            paidAt: UInt64(payment.paidAt),
            filedAt: UInt64(max(0, payment.filedAt)),
            evidenceMask: payment.evidenceMask,
            status: payment.status,
            refundBPS: payment.refundBps,
            disputeWindow: disputeWindow
        )
    }

    private func displayPayment(
        id: UInt64,
        merchantAddress: String,
        policyID: UInt64,
        amount: USDCAmount,
        paidAt: UInt64,
        filedAt: UInt64,
        evidenceMask: Int32,
        status: Int32,
        refundBPS: Int32?,
        disputeWindow: UInt64
    ) -> DemoPayment {
        let paidDate = Date(timeIntervalSince1970: TimeInterval(paidAt))
        let protectionEnds = paidDate.addingTimeInterval(TimeInterval(disputeWindow))
        let elapsed = Date().timeIntervalSince(paidDate)
        let progress = disputeWindow == 0
            ? 1
            : min(max(elapsed / TimeInterval(disputeWindow), 0), 1)
        let shortMerchant = shortAddress(merchantAddress)
        let context = orderContexts[id]
        let imageURL = context?.imageHash.map {
            configuration.apiURL.appending(path: "api/orders/image/\($0)")
        }
        return DemoPayment(
            id: id,
            merchant: context?.itemName ?? "Merchant \(shortMerchant)",
            item: context == nil ? "Policy #\(policyID)" : "Merchant \(shortMerchant)",
            merchantSymbol: "shippingbox.fill",
            merchantImageURL: imageURL,
            amount: amount,
            date: paidDate,
            state: displayState(
                status: status,
                filedAt: filedAt,
                evidenceMask: evidenceMask,
                refundBPS: refundBPS
            ),
            policyName: "Policy #\(policyID)",
            protectionEnds: protectionEnds,
            progress: progress,
            orderReference: "Payment #\(id)"
        )
    }

    private func displayState(
        status: Int32,
        filedAt: UInt64,
        evidenceMask: Int32,
        refundBPS: Int32?
    ) -> DemoPaymentState {
        switch status {
        case Int32(PaymentStatus.paid.rawValue):
            return .protected
        case Int32(PaymentStatus.disputed.rawValue):
            return filedAt > 0 && evidenceMask == 0 ? .actionNeeded : .underReview
        case Int32(PaymentStatus.settled.rawValue):
            return (refundBPS ?? 0) > 0 ? .refunded : .released
        default:
            return .released
        }
    }

    private func updateState(paymentID: UInt64, state: DemoPaymentState) {
        if let index = payments.firstIndex(where: { $0.id == paymentID }) {
            payments[index] = replacingState(of: payments[index], with: state)
        }
        if let index = merchantPayments.firstIndex(where: { $0.id == paymentID }) {
            merchantPayments[index] = replacingState(of: merchantPayments[index], with: state)
        }
    }

    private func replacingState(
        of payment: DemoPayment,
        with state: DemoPaymentState
    ) -> DemoPayment {
        DemoPayment(
            id: payment.id,
            merchant: payment.merchant,
            item: payment.item,
            merchantSymbol: payment.merchantSymbol,
            merchantImageURL: payment.merchantImageURL,
            amount: payment.amount,
            date: payment.date,
            state: state,
            policyName: payment.policyName,
            protectionEnds: payment.protectionEnds,
            progress: payment.progress,
            orderReference: payment.orderReference
        )
    }

    private func shortAddress(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))…\(value.suffix(4))"
    }
}

#if DEBUG
extension AppEnvironment {
    static func preview() -> AppEnvironment {
        let environment = AppEnvironment(
            configuration: .live,
            accountSession: .preview()
        )
        environment.paymentStore.installPreviewData()
        return environment
    }
}

private extension BuyerPaymentStore {
    func installPreviewData() {
        payments = DemoCatalog.payments
        merchantPayments = DemoCatalog.payments
        balance = DemoCatalog.balance
    }
}
#endif
