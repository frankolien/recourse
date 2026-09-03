import Foundation
import Observation

/// What a movement was, as opposed to which way it went.
///
/// The explorer knows the function that moved the money. `transfer` is a send;
/// `transferWithAuthorization` is a cheque or an invoice, told apart by whether the
/// counterparty is someone this account has billed or been billed by; a swap is a
/// conversion; the vault and the old escrow are named by their addresses.
enum HistoryKind: Equatable, Sendable {
    case sent
    case received
    case chequeCashed
    case chequeYouCashed
    case invoicePaid
    case invoiceCollected
    case converted
    case earnDeposit
    case earnWithdrawal
    case escrow

    var title: String {
        switch self {
        case .sent: "Sent"
        case .received: "Received"
        case .chequeCashed: "Cheque cashed"
        case .chequeYouCashed: "Cheque cashed"
        case .invoicePaid: "Invoice paid"
        case .invoiceCollected: "Invoice collected"
        case .converted: "Converted"
        case .earnDeposit: "Put into Earn"
        case .earnWithdrawal: "Taken out of Earn"
        case .escrow: "Escrow"
        }
    }

    var symbol: String {
        switch self {
        case .sent: "arrow.up.right"
        case .received: "arrow.down.left"
        case .chequeCashed, .chequeYouCashed: "doc.text.fill"
        case .invoicePaid, .invoiceCollected: "arrow.down.left.circle.fill"
        case .converted: "arrow.left.arrow.right"
        case .earnDeposit, .earnWithdrawal: "chart.bar.fill"
        case .escrow: "lock.fill"
        }
    }
}

struct HistoryEntry: Identifiable, Equatable, Sendable {
    let transfer: TokenTransfer
    let kind: HistoryKind
    /// True when the wallet's balance went up.
    let incoming: Bool
    var id: String { transfer.id }

    var counterparty: String { incoming ? transfer.from : transfer.to }
}

/// The addresses that give a transfer its name.
struct HistoryContext: Sendable {
    let me: String
    let usdc: String
    let eurc: String?
    let vault: String
    let escrow: String
    let fxRouter: String?
    /// People this account has issued invoices to. A signed authorization arriving
    /// from one of them is an invoice being collected, not a cheque.
    let invoicePayers: Set<String>
    /// People who have invoiced this account.
    let invoiceIssuers: Set<String>

    /// Names every transfer, with the whole list in view.
    ///
    /// A conversion is two legs of one transaction, USDC one way and EURC the other,
    /// and neither leg names the other. The transaction hash does, so any hash carrying
    /// more than one token is a conversion whatever address sat in the middle. That
    /// holds for the pair, the router, and whichever venue comes next.
    func classify(_ transfers: [TokenTransfer]) -> [HistoryEntry] {
        var tokensByHash: [String: Set<String>] = [:]
        for transfer in transfers {
            tokensByHash[transfer.hash, default: []].insert(transfer.token)
        }
        let conversions = Set(tokensByHash.filter { $0.value.count > 1 }.keys)
        return transfers.compactMap { classify($0, conversions: conversions) }
    }

    func classify(_ transfer: TokenTransfer, conversions: Set<String> = []) -> HistoryEntry? {
        let incoming = transfer.to == me
        let outgoing = transfer.from == me
        guard incoming || outgoing else { return nil }
        let counterparty = incoming ? transfer.from : transfer.to

        let kind: HistoryKind
        if counterparty == vault {
            kind = incoming ? .earnWithdrawal : .earnDeposit
        } else if counterparty == escrow {
            kind = .escrow
        } else if conversions.contains(transfer.hash) || transfer.token != usdc {
            kind = .converted
        } else if let fxRouter, counterparty == fxRouter {
            kind = .converted
        } else if transfer.method.hasPrefix("swap") {
            kind = .converted
        } else if transfer.method == "transferWithAuthorization" {
            if incoming {
                kind = invoicePayers.contains(counterparty) ? .invoiceCollected : .chequeYouCashed
            } else {
                kind = invoiceIssuers.contains(counterparty) ? .invoicePaid : .chequeCashed
            }
        } else {
            kind = incoming ? .received : .sent
        }
        return HistoryEntry(transfer: transfer, kind: kind, incoming: incoming)
    }
}

/// How far back the balance chart looks.
enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case halfYear = "6M"
    case year = "1Y"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .halfYear: 182 * 86_400
        case .year: 365 * 86_400
        }
    }
}

/// The balance as it was, worked backwards from the balance as it is.
///
/// There is no historical balance to read anywhere, but there is the current one and
/// every transfer that led to it, and undoing transfers in reverse order is enough.
/// Fees are the one thing this misses: Arc charges them in USDC and they leave no
/// transfer event, so the reconstruction drifts by the gas spent over the range. On a
/// chart of thin grey bars that is invisible; on a statement it would not be, which is
/// why this feeds a chart and nothing else.
enum BalanceSeries {
    static func samples(
        current: UInt64,
        transfers: [TokenTransfer],
        me: String,
        token: String,
        range: HistoryRange,
        now: Date,
        count: Int
    ) -> [UInt64] {
        guard count > 1 else { return [current] }
        let relevant = transfers
            .filter { $0.token == token && ($0.from == me || $0.to == me) }
            .sorted { $0.timestamp > $1.timestamp }

        func balance(at moment: Date) -> UInt64 {
            var value = current
            for transfer in relevant where transfer.timestamp > moment {
                if transfer.to == me {
                    value = value >= transfer.value ? value - transfer.value : 0
                } else {
                    value = value.addingReportingOverflow(transfer.value).partialValue
                }
            }
            return value
        }

        let start = now.addingTimeInterval(-range.seconds)
        return (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            return balance(at: start.addingTimeInterval(range.seconds * fraction))
        }
    }
}

/// Every movement on the wallet, from the explorer, named.
@MainActor
@Observable
final class TransferHistory {
    private let configuration: AppConfiguration
    private let signer: any BuyerSigner
    private let explorer: any ExplorerAPI

    private(set) var transfers: [TokenTransfer] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var me: String?

    init(configuration: AppConfiguration, signer: any BuyerSigner, explorer: any ExplorerAPI) {
        self.configuration = configuration
        self.signer = signer
        self.explorer = explorer
    }

    private static let minimumInterval: TimeInterval = 45

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.minimumInterval {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let address = try await signer.address()
            me = address.value.lowercased()
            transfers = try await explorer.tokenTransfers(for: address)
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = "History could not be loaded. Pull to retry."
        }
    }

    func context(invoicePayers: Set<String>, invoiceIssuers: Set<String>) -> HistoryContext? {
        guard let me else { return nil }
        return HistoryContext(
            me: me,
            usdc: configuration.usdcAddress.value.lowercased(),
            eurc: configuration.eurcAddress?.value.lowercased(),
            vault: configuration.settlementVaultAddress.value.lowercased(),
            escrow: configuration.escrowAddress.value.lowercased(),
            fxRouter: configuration.fxRouterAddress?.value.lowercased(),
            invoicePayers: invoicePayers,
            invoiceIssuers: invoiceIssuers
        )
    }

    func entries(invoicePayers: Set<String>, invoiceIssuers: Set<String>) -> [HistoryEntry] {
        guard let context = context(invoicePayers: invoicePayers, invoiceIssuers: invoiceIssuers) else {
            return []
        }
        return context.classify(transfers)
    }

    func balanceSamples(current: USDCAmount?, range: HistoryRange, count: Int, now: Date = Date()) -> [UInt64] {
        guard let me, let current else { return [] }
        return BalanceSeries.samples(
            current: current.baseUnits,
            transfers: transfers,
            me: me,
            token: configuration.usdcAddress.value.lowercased(),
            range: range,
            now: now,
            count: count
        )
    }
}
