import Foundation
import Observation

enum TeamError: Error, Equatable {
    /// No Safe yet, so nothing that can sign for a team.
    case noAccount
    case notASigner
    /// The typed data the service sent hashes to something other than the hash it
    /// named. Both are kept so the screen can show them side by side.
    case hashMismatch(expected: String, computed: String)
    case cannotVeto(String)

    var message: String {
        switch self {
        case .noAccount: "Finish setting up your account before acting for a team."
        case .notASigner: "This account is not a member of that treasury."
        case .hashMismatch: "The proposal's data does not hash to the hash the service sent. Nothing was signed."
        case .cannotVeto(let reason): reason
        }
    }
}

/// The treasuries this account belongs to, and what it can do in each.
///
/// A store rather than screen state because Home needs the same answer the Team
/// screens do: whether there is a treasury at all, and how many proposals are
/// waiting on this account. The Safe is the member, so everything here is empty
/// until the account has one, and the signer id is derived from it rather than
/// stored.
@MainActor
@Observable
final class TeamStore {
    private let configuration: AppConfiguration
    private let session: AccountSession
    private let smartAccounts: SmartAccountStore
    private let api: any OlienAPI
    private let makeSubmitter: @MainActor () -> (any ArcSubmitter)?

    private(set) var accounts: [OlienSummary] = []
    private(set) var details: [String: OlienAccount] = [:]
    private(set) var proposals: [String: [OlienProposal]] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    init(
        configuration: AppConfiguration,
        session: AccountSession,
        smartAccounts: SmartAccountStore,
        api: any OlienAPI,
        makeSubmitter: @escaping @MainActor () -> (any ArcSubmitter)?
    ) {
        self.configuration = configuration
        self.session = session
        self.smartAccounts = smartAccounts
        self.api = api
        self.makeSubmitter = makeSubmitter
    }

    /// The id this account signs under, once it has a Safe.
    var mySignerID: String? {
        smartAccounts.safeAddress.map(OlienSigning.signerID(for:))
    }

    var isMember: Bool { !accounts.isEmpty }

    /// Open proposals still missing this account's approval, across every treasury.
    var waitingForMe: [OlienProposal] {
        guard let mine = mySignerID else { return [] }
        return proposals.values
            .flatMap { $0 }
            .filter { $0.status == .open && $0.isMissing(mine) }
    }

    func summary(_ address: String) -> OlienSummary? {
        accounts.first { $0.id == address.lowercased() }
    }

    func account(_ address: String) -> OlienAccount? {
        details[address.lowercased()]
    }

    func proposals(for address: String) -> [OlienProposal] {
        proposals[address.lowercased()] ?? []
    }

    func proposal(account: String, txHash: String) -> OlienProposal? {
        proposals(for: account).first { $0.id == txHash.lowercased() }
    }

    /// How stale the list may get before a background caller reloads it. Home polls
    /// every ten seconds; the Team screens pass `force` and get it every time.
    private static let minimumInterval: TimeInterval = 45

    private let cache = SnapshotCache.shared
    private static let snapshotKey = "team"

    private struct Snapshot: Codable {
        let accounts: [OlienSummary]
        let details: [String: OlienAccount]
        let proposals: [String: [OlienProposal]]
    }

    // The account whose teams are held. Starts unequal to any real scope so the first
    // refresh opens that account's own snapshot, never the last person's treasuries.
    private var loadedScope: String? = "unloaded"

    private func adoptScope() {
        let scope = ActiveAccount.scope
        guard scope != loadedScope else { return }
        loadedScope = scope
        lastUpdated = nil
        errorMessage = nil
        let snapshot = cache.load(Snapshot.self, key: Self.snapshotKey, scope: scope)
        accounts = snapshot?.accounts ?? []
        details = snapshot?.details ?? [:]
        proposals = snapshot?.proposals ?? [:]
    }

    private func persist() {
        cache.save(Snapshot(accounts: accounts, details: details, proposals: proposals), key: Self.snapshotKey, scope: loadedScope)
    }

    /// Ask the service again. A failure leaves the teams as they were and says so.
    func refresh(force: Bool = false) async {
        adoptScope()
        guard !isLoading else { return }
        guard session.isAuthenticated else {
            clear()
            return
        }
        // A Safe still being looked up is not the same as no Safe: the teams stay on
        // screen until the account is known to have none.
        guard smartAccounts.safeAddress != nil else {
            if smartAccounts.phase == SmartAccountStore.Phase.none { clear() }
            return
        }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.minimumInterval {
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let list = try await session.withAccessToken { try await api.accounts(accessToken: $0) }
            var queue: [String: [OlienProposal]] = [:]
            for summary in list {
                queue[summary.id] = try await session.withAccessToken {
                    try await api.proposals(account: summary.address, statuses: nil, accessToken: $0)
                }
            }
            guard loadedScope == ActiveAccount.scope else { return }
            accounts = list
            proposals = queue
            details = details.filter { entry in list.contains { $0.id == entry.key } }
            errorMessage = nil
            lastUpdated = Date()
            persist()
        } catch AccountSessionError.signedOut {
            clear()
        } catch {
            errorMessage = "Teams could not be loaded. Pull to retry."
        }
    }

    /// One treasury in full: its members and its whole queue.
    func refreshAccount(_ address: String) async {
        guard session.isAuthenticated, smartAccounts.safeAddress != nil else {
            clear()
            return
        }
        do {
            let (view, queue) = try await session.withAccessToken { token in
                async let view = api.account(address: address, accessToken: token)
                async let queue = api.proposals(account: address, statuses: nil, accessToken: token)
                return try await (view, queue)
            }
            guard loadedScope == ActiveAccount.scope else { return }
            details[view.id] = view
            proposals[view.id] = queue
            errorMessage = nil
            persist()
        } catch AccountSessionError.signedOut {
            clear()
        } catch {
            errorMessage = "This treasury could not be loaded. Pull to retry."
        }
    }

    private func clear() {
        accounts = []
        details = [:]
        proposals = [:]
        lastUpdated = nil
        errorMessage = nil
        cache.remove(key: Self.snapshotKey, scope: loadedScope)
    }

    // MARK: What this account may do

    func mySigner(in account: OlienAccount) -> OlienSigner? {
        guard let mine = mySignerID else { return nil }
        return account.signer(id: mine)
    }

    func hasConfirmed(_ proposal: OlienProposal) -> Bool {
        guard let mine = mySignerID else { return false }
        return proposal.hasConfirmation(from: mine)
    }

    func canApprove(_ proposal: OlienProposal, in account: OlienAccount) -> Bool {
        proposal.status == .open
            && mySigner(in: account)?.canApprove == true
            && !hasConfirmed(proposal)
    }

    /// Veto is offered only where the chain would count it: a scheduled change, a
    /// signer holding VETO, not the one the change excludes, not already counted.
    func canVeto(_ proposal: OlienProposal, in account: OlienAccount) -> Bool {
        guard proposal.status == .scheduled,
              let mine = mySignerID,
              let signer = mySigner(in: account),
              signer.canVeto,
              !proposal.hasVeto(from: mine) else { return false }
        if proposal.scheduledExcluded?.lowercased() == mine, proposal.path != "recovery" {
            return false
        }
        return true
    }

    func canExecuteScheduled(_ proposal: OlienProposal, now: Date = Date()) -> Bool {
        guard proposal.status == .scheduled, let readyAt = proposal.scheduledReadyDate else { return false }
        return readyAt <= now
    }

    // MARK: Acting

    /// Sign the proposal's hash as the Safe and hand the service the confirmation.
    ///
    /// The hash is recomputed from the typed data first. The service names a hash
    /// and sends the data it claims produced it; a phone that signs the name without
    /// checking would sign whatever the data really is.
    func approve(_ proposal: OlienProposal) async throws -> OlienProposal {
        guard let signer = smartAccounts.safeSigner else { throw TeamError.noAccount }
        let safe = await signer.safe
        let computed = try OlienSigning.transactionHash(typedData: proposal.typedDataJSON())
        guard computed.value.lowercased() == proposal.txHash.lowercased() else {
            throw TeamError.hashMismatch(expected: proposal.txHash, computed: computed.value)
        }
        // The Olien hands the Safe the hash itself; the Safe frames it as a message
        // and both keys sign that. No second hash in between.
        let messageHash = SafeHashing.messageHash(
            safe: safe,
            chainID: configuration.chainID,
            digest: OlienSigning.bytes(of: computed)
        )
        let signature = try await signer.signSafeHash(messageHash)
        let updated = try await session.withAccessToken {
            try await api.confirm(
                account: proposal.account,
                txHash: proposal.txHash,
                signerID: OlienSigning.signerID(for: safe),
                signature: signature.hexString,
                accessToken: $0
            )
        }
        store(updated)
        return updated
    }

    /// The relayer sends it and pays; the phone only asks.
    func execute(_ proposal: OlienProposal) async throws -> OlienProposal {
        let updated = try await session.withAccessToken {
            try await api.execute(account: proposal.account, txHash: proposal.txHash, accessToken: $0)
        }
        store(updated)
        return updated
    }

    func executeScheduled(_ proposal: OlienProposal) async throws -> OlienProposal {
        let updated = try await session.withAccessToken {
            try await api.executeScheduled(account: proposal.account, txHash: proposal.txHash, accessToken: $0)
        }
        store(updated)
        return updated
    }

    /// A veto is the Safe's own transaction: the Olien records it from `msg.sender`.
    /// The service is asked for the call first, so a veto that would no longer count
    /// is refused before any gas is spent, and its bytes must be the ones this phone
    /// builds itself.
    func veto(_ proposal: OlienProposal) async throws -> ChainHash {
        guard let submitter = makeSubmitter(), let mine = mySignerID else { throw TeamError.noAccount }
        let hash = try ChainHash(proposal.txHash)
        let olien = try EthereumAddress(proposal.account)
        let call = try await session.withAccessToken {
            try await api.vetoCall(account: proposal.account, txHash: proposal.txHash, accessToken: $0)
        }
        guard call.signerIds.contains(where: { $0.lowercased() == mine }) else {
            throw TeamError.cannotVeto("Your veto would not count on this change any more.")
        }
        let data = OlienSigning.vetoCalldata(hash: hash)
        guard call.data.lowercased() == data.hexString, call.to.lowercased() == olien.value.lowercased() else {
            throw TeamError.cannotVeto("The veto the service described is not the one this phone built. Nothing was sent.")
        }
        let transaction = try await submitter.submit(to: olien, data: data)
        await refreshAccount(proposal.account)
        return transaction
    }

    private func store(_ proposal: OlienProposal) {
        var queue = proposals(for: proposal.account)
        if let index = queue.firstIndex(where: { $0.id == proposal.id }) {
            queue[index] = proposal
        } else {
            queue.insert(proposal, at: 0)
        }
        proposals[proposal.account.lowercased()] = queue
    }
}
