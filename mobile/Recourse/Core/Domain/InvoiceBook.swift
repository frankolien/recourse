import Foundation
import Observation

/// Where an invoice stands.
///
/// Only `collected` comes from the chain. Everything else is the server's row plus a
/// clock, which is fine because none of it is a claim about money having moved: an
/// invoice that says "signed" is saying a signature exists, and the token is still the
/// only thing that decides whether it was used.
enum InvoiceStanding: Equatable, Sendable {
    /// Nobody has answered it, and it can still be answered.
    case open
    /// Nobody answered it in time.
    case overdue
    /// The payer signed. The money is collectable and has not been collected.
    case signed
    /// The authorization was submitted; the money moved.
    case collected
    /// Signed, then the window closed before the issuer submitted it. The payer's
    /// obligation is over and the issuer let it lapse.
    case lapsed
    /// The issuer withdrew the request before anyone answered.
    case cancelled

    /// Whether anyone still has something to do about it.
    var isLive: Bool {
        switch self {
        case .open, .signed: true
        case .overdue, .collected, .lapsed, .cancelled: false
        }
    }
}

struct InvoiceEntry: Identifiable, Equatable, Sendable {
    let stored: StoredInvoice
    let standing: InvoiceStanding

    var id: Int64 { stored.invoiceId }
}

/// Both directions of billing: what you are owed, and what you owe.
///
/// Kept apart from the cheque book because the questions are opposite. A cheque you
/// hold is money you may take; an invoice you hold is money someone wants from you, and
/// showing the two in one total would produce a number that means nothing.
@MainActor
@Observable
final class InvoiceBook {
    private let accountSession: AccountSession
    private let makeGateway: () throws -> any ContractGateway
    private let api: any InvoiceAPI

    /// Invoices this account issued: money owed to you.
    private(set) var issued: [InvoiceEntry] = []
    /// Invoices addressed to this account: money you owe.
    private(set) var received: [InvoiceEntry] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    init(
        accountSession: AccountSession,
        api: any InvoiceAPI,
        makeGateway: @escaping () throws -> any ContractGateway
    ) {
        self.accountSession = accountSession
        self.api = api
        self.makeGateway = makeGateway
    }

    /// Money others still owe you: issued, unanswered or answered but uncollected.
    var owedToYou: USDCAmount {
        total(issued.filter(\.standing.isLive))
    }

    /// Money you still owe: addressed to you and not yet dealt with.
    var youOwe: USDCAmount {
        total(received.filter(\.standing.isLive))
    }

    /// Signed invoices sitting there waiting for you to submit them. This is the one
    /// number with an action attached, so it is what the app nudges about.
    var readyToCollect: [InvoiceEntry] {
        issued.filter { $0.standing == .signed }
    }

    var readyToCollectTotal: USDCAmount {
        total(readyToCollect)
    }

    /// Invoices asking you for money that you have not answered.
    var awaitingYou: [InvoiceEntry] {
        received.filter { $0.standing == .open }
    }

    private func total(_ entries: [InvoiceEntry]) -> USDCAmount {
        USDCAmount(
            baseUnits: entries.reduce(into: UInt64(0)) {
                $0 = $0.addingReportingOverflow($1.stored.amountBaseUnits).partialValue
            }
        )
    }

    /// How stale the book may get before a background caller reloads it. Same reasoning
    /// as the cheque book: every unsettled invoice costs a chain read.
    private static let minimumInterval: TimeInterval = 45

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.minimumInterval {
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let (inbox, outbox) = try await accountSession.withAccessToken { token in
                async let inbox = api.inbox(accessToken: token)
                async let outbox = api.outbox(accessToken: token)
                return try await (inbox, outbox)
            }
            received = await resolve(inbox)
            issued = await resolve(outbox)
            errorMessage = nil
            lastUpdated = Date()
        } catch AccountSessionError.signedOut {
            received = []
            issued = []
        } catch {
            errorMessage = "Invoices could not be loaded. Pull to retry."
        }
    }

    /// A spent nonce can never become unspent, so this cache cannot go stale.
    private var knownSpent: Set<String> = []

    /// Works out each invoice's standing, reading the chain only where the answer is
    /// not already settled.
    ///
    /// An unsigned invoice needs no read at all: with no signature in existence nobody
    /// could have collected it, so the nonce being unspent is guaranteed rather than
    /// worth asking about.
    private func resolve(_ rows: [StoredInvoice]) async -> [InvoiceEntry] {
        let gateway = try? makeGateway()
        let now = Date()
        var entries: [InvoiceEntry] = []

        for row in rows {
            var collected = false
            if row.isSigned {
                let key = row.nonce.lowercased()
                collected = knownSpent.contains(key)
                if !collected, let gateway, let payer = try? EthereumAddress(row.payer) {
                    collected = (try? await gateway.authorizationState(
                        authorizer: payer,
                        nonce: row.nonceBytes
                    )) ?? false
                    if collected { knownSpent.insert(key) }
                }
            }
            entries.append(
                InvoiceEntry(stored: row, standing: standing(for: row, collected: collected, now: now))
            )
        }
        return entries
    }

    private func standing(for row: StoredInvoice, collected: Bool, now: Date) -> InvoiceStanding {
        if collected { return .collected }
        if row.isCancelled { return .cancelled }
        let expired = row.dueAt <= now
        if row.isSigned { return expired ? .lapsed : .signed }
        return expired ? .overdue : .open
    }
}
