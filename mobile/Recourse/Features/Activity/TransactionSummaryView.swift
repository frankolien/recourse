import SwiftUI

/// One movement, on its own page: what it was, who was on the other end, and the
/// facts underneath. The explorer is one tap further, inside the app, for anyone who
/// wants the raw transaction rather than the sentence.
struct TransactionSummaryView: View {
    let entry: HistoryEntry
    /// The other party as the list names them: an @handle, a short address, or Earn.
    let counterpartyName: String
    let network: String
    let explorerURL: URL
    let isUSDC: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showsExplorer = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Summary")
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
                .padding(.top, 22)

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                BrandMarkView(mark: isUSDC ? .usdc : .eurc, height: 92)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: entry.kind.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(entry.incoming ? RecourseColor.ledger : RecourseColor.nightText)
                            .frame(width: 32, height: 32)
                            .background(RecourseColor.nightChip, in: Circle())
                            .overlay(Circle().stroke(RecourseColor.night, lineWidth: 3))
                            .offset(x: 4, y: 4)
                    }
                    .padding(.bottom, 8)

                Text(entry.kind.title)
                    .font(.recourse(34, .bold))
                    .foregroundStyle(RecourseColor.nightText)

                Text(subtitle)
                    .font(.recourse(17, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)

                Button {
                    showsExplorer = true
                } label: {
                    Text("View Transaction")
                        .font(.recourse(17, .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                        .padding(.top, 14)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            facts
                .padding(.horizontal, 20)

            Button {
                dismiss()
            } label: {
                Text("Dismiss")
                    .font(.recourse(17, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(RecourseColor.nightChip, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecourseColor.night.ignoresSafeArea())
        .sheet(isPresented: $showsExplorer) {
            SafariWebView(url: explorerURL)
        }
    }

    private var subtitle: String {
        switch entry.kind {
        case .earnDeposit, .earnWithdrawal, .converted, .escrow: network
        default: "\(entry.incoming ? "From" : "To") \(counterpartyName)"
        }
    }

    // The same rows every time, in the order someone checks them: when, how much,
    // where, and whether it went through. The explorer only lists movements that
    // did, so status is a reassurance rather than a question.
    private var facts: some View {
        VStack(spacing: 0) {
            fact("Date") {
                Text(entry.transfer.timestamp.formatted(.dateTime.hour().minute().day().month(.abbreviated).year()))
                    .foregroundStyle(RecourseColor.nightText)
            }
            divider
            VStack(alignment: .leading, spacing: 12) {
                Text("Balance Change")
                    .font(.recourse(15, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                HStack(spacing: 10) {
                    BrandMarkView(mark: isUSDC ? .usdc : .eurc, height: 26)
                    Text(entry.transfer.symbol)
                        .font(.recourse(15, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    Spacer()
                    Text("\(entry.incoming ? "+" : "-")\(USDCAmount(baseUnits: entry.transfer.value).decimalString)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(entry.incoming ? RecourseColor.ledger : RecourseColor.nightText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            divider
            fact("Network") {
                Text(network)
                    .foregroundStyle(RecourseColor.nightText)
            }
            divider
            fact("Status") {
                Text("Successful")
                    .foregroundStyle(RecourseColor.ledger)
            }
        }
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(RecourseColor.nightLine)
    }

    private func fact<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label)
                .font(.recourse(15, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            value()
                .font(.recourse(15, .semibold))
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }
}
