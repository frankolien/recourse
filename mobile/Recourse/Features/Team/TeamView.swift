import SwiftUI

/// The treasuries this account belongs to.
///
/// A member does not open a treasury; a treasury names them. So there is nothing to
/// create here, and the empty state says how to be added rather than offering a
/// button that would do nothing.
struct TeamView: View {
    let environment: AppEnvironment

    private var store: TeamStore { environment.teamStore }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.accounts.isEmpty {
                    empty
                } else {
                    ForEach(store.accounts) { account in
                        Button {
                            environment.router.push(.teamAccount(account.address))
                        } label: {
                            row(account)
                        }
                        .buttonStyle(.plain)
                        if account.id != store.accounts.last?.id {
                            Divider()
                                .overlay(RecourseColor.nightLine)
                                .padding(.leading, 56)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Teams")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refresh(force: true)
        }
        .task {
            while !Task.isCancelled {
                await store.refresh(force: true)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func row(_ account: OlienSummary) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(account.openProposals > 0 ? RecourseColor.ledger : RecourseColor.nightMuted)
                .frame(width: 42, height: 42)
                .background(RecourseColor.nightChip, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(1)
                Text(queueLine(account))
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(account.usdc.decimalString)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                Text(account.shortAddress)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func queueLine(_ account: OlienSummary) -> String {
        var parts: [String] = []
        if account.openProposals > 0 {
            parts.append(account.openProposals == 1 ? "1 open proposal" : "\(account.openProposals) open proposals")
        }
        if account.scheduledChanges > 0 {
            parts.append(account.scheduledChanges == 1 ? "1 scheduled change" : "\(account.scheduledChanges) scheduled changes")
        }
        if parts.isEmpty {
            return "\(account.threshold) of \(account.signerCount) to approve"
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isLoading, store.lastUpdated == nil {
                HStack(spacing: 12) {
                    ProgressView().tint(RecourseColor.nightText)
                    Text("Looking for your teams")
                        .font(.recourse(13, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                }
            } else if !environment.smartAccounts.isLive {
                Text("Your account is not ready for teams yet")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text("A treasury adds your account as a member, and it is the three-key account that signs. Finish setting it up under Keys first.")
                    .font(.recourse(12.5))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.recourse(13, .medium))
                    .foregroundStyle(RecourseColor.nightText)
            } else {
                Text("No teams yet. Ask a treasury to add your @handle.")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("When a treasury on Arc names your account as a member, it appears here. You approve its payments with Face ID and it never holds a key of yours.")
                    .font(.recourse(12.5))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 26)
        .padding(.trailing, 24)
    }
}
