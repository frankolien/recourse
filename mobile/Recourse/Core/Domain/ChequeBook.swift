import Foundation
import Observation

/// Where a cheque stands, as opposed to what the server remembers about it.
///
/// Only the spent ones come from the chain; the rest are clock readings. That is why
/// `expired` is worth a case of its own: nothing on chain marks an expiry, so if the
/// app did not work it out, a cheque would simply stop working with no explanation.
enum ChequeStanding: Equatable, Sendable {
    case cashable
    /// Written to start later. Rare, but the field is signed over so it can happen.
    case notYet(from: Date)
    case expired
    /// The nonce is spent. Cashed or voided, and the app says which from what it saw.
    case cashed
    case voided

    var isLive: Bool {
        switch self {
        case .cashable, .notYet: true
        case .expired, .cashed, .voided: false
        }
    }
}

/// A cheque with its standing worked out.
struct ChequeEntry: Identifiable, Equatable, Sendable {
    let stored: StoredCheque
    let standing: ChequeStanding

    var id: Int64 { stored.chequeId }
}

/// Both sides of the cheque book, and the arithmetic that keeps a writer honest.
///
/// The arithmetic is the reason this is a store rather than a screen's state. EIP-3009
/// does not reserve anything: writing three 10 USDC cheques against a 15 USDC balance
/// produces two that cash and one that bounces, and the token has no opinion about it.
/// So the app keeps the opinion. Every live cheque this account has written is
/// committed, and what is left is what can honestly be promised to anyone else.
@MainActor
@Observable
final class ChequeBook {
    private let configuration: AppConfiguration
    private let accountSession: AccountSession
    private let makeGateway: () throws -> any ContractGateway
    private let api: any ChequeAPI

    private(set) var received: [ChequeEntry] = []
    private(set) var written: [ChequeEntry] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    init(
        configuration: AppConfiguration,
        accountSession: AccountSession,
        api: any ChequeAPI,
        makeGateway: @escaping () throws -> any ContractGateway
    ) {
        self.configuration = configuration
        self.accountSession = accountSession
        self.api = api
        self.makeGateway = makeGateway
    }

    /// USDC this account has promised away and not yet had taken.
    var committed: USDCAmount {
        USDCAmount(
            baseUnits: written
                .filter { $0.standing.isLive }
                .reduce(into: UInt64(0)) {
                    $0 = $0.addingReportingOverflow($1.stored.amountBaseUnits).partialValue
                }
        )
    }

    var liveWrittenCount: Int {
        written.filter { $0.standing.isLive }.count
    }

    var cashableCount: Int {
        received.filter { $0.standing == .cashable }.count
    }

    var cashableTotal: USDCAmount {
        USDCAmount(
            baseUnits: received
                .filter { $0.standing == .cashable }
                .reduce(into: UInt64(0)) {
                    $0 = $0.addingReportingOverflow($1.stored.amountBaseUnits).partialValue
                }
        )
    }

    /// What is safe to write another cheque against, given what is already out there.
    ///
    /// Saturating rather than negative: a balance below what has been committed is a
    /// real situation (the writer spent it elsewhere) and the answer the screen needs
    /// is "nothing", not a number below zero.
    func available(balance: USDCAmount?) -> USDCAmount {
        guard let balance else { return USDCAmount(baseUnits: 0) }
        return USDCAmount(baseUnits: balance.baseUnits > committed.baseUnits
            ? balance.baseUnits - committed.baseUnits
            : 0)
    }

    /// How stale the book may get before a background caller is allowed to reload it.
    ///
    /// Home polls every ten seconds and each cheque costs a chain read, so without this
    /// a full book would hold a public RPC open permanently. A person pulling to
    /// refresh passes `force` and waits for nobody.
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
            written = await resolve(outbox)
            errorMessage = nil
            lastUpdated = Date()
        } catch AccountSessionError.signedOut {
            received = []
            written = []
        } catch {
            errorMessage = "Cheques could not be loaded. Pull to retry."
        }
    }

    /// Remembered locally because the token records one bit for both outcomes.
    ///
    /// Asking the chain whether a nonce is spent cannot tell cashed from voided, and
    /// reconstructing it from logs would mean an archive query per cheque. The device
    /// that pressed void already knows, so it writes that down.
    private var voidedNonces: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: Self.voidedKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.voidedKey)
        }
    }

    private static var voidedKey: String {
        ActiveAccount.scope.map { "recourse.cheques.voided.\($0)" } ?? "recourse.cheques.voided"
    }

    func rememberVoided(nonce: String) {
        voidedNonces.insert(nonce.lowercased())
    }

    /// Nonces the chain has already reported spent.
    ///
    /// A spent nonce can never become unspent, so this is a cache that cannot go stale.
    /// It is what keeps a settled cheque from costing a chain read on every refresh for
    /// the rest of its life.
    private var knownSpent: Set<String> = []

    /// Fills in each cheque's standing from the chain, one read per cheque.
    ///
    /// Sequential on purpose: a page of cheques is short, and a burst of parallel
    /// eth_calls against a public RPC is the fastest way to get rate limited into
    /// showing nothing at all. Expired cheques are still read once, because a cheque
    /// can be cashed and then expire, and calling that one "expired" would be telling
    /// someone their money is still theirs when it is not.
    private func resolve(_ rows: [StoredCheque]) async -> [ChequeEntry] {
        let gateway = try? makeGateway()
        let voided = voidedNonces
        let now = Date()
        var entries: [ChequeEntry] = []

        for row in rows {
            let key = row.nonce.lowercased()
            var spent = knownSpent.contains(key)
            if !spent, let gateway, let writer = try? EthereumAddress(row.from) {
                spent = (try? await gateway.authorizationState(
                    authorizer: writer,
                    nonce: row.nonceBytes
                )) ?? false
                if spent { knownSpent.insert(key) }
            }
            entries.append(
                ChequeEntry(stored: row, standing: standing(for: row, spent: spent, voided: voided, now: now))
            )
        }
        return entries
    }

    private func standing(
        for row: StoredCheque,
        spent: Bool,
        voided: Set<String>,
        now: Date
    ) -> ChequeStanding {
        if spent {
            return voided.contains(row.nonce.lowercased()) ? .voided : .cashed
        }
        let startsAt = Date(timeIntervalSince1970: TimeInterval(UInt64(row.validAfter) ?? 0))
        if startsAt > now { return .notYet(from: startsAt) }
        if row.expiresAt <= now { return .expired }
        return .cashable
    }
}
