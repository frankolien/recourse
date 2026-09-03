import SwiftUI

/// Help, and the answers people actually need before they trust an app with money.
///
/// Rewritten when the protected checkout came out: the old version was three rows about
/// policies, evidence and verdicts, which described a product this app no longer is.
/// What replaces it is the set of questions someone reasonably asks about a wallet
/// holding their USDC, answered rather than routed.
struct SupportView: View {
    @State private var expanded: String?

    private struct Answer: Identifiable {
        let id: String
        let question: String
        let body: String
    }

    private let answers: [Answer] = [
        Answer(
            id: "keys",
            question: "Who can move my money?",
            body: "Only this device. Your signing key is generated here and stored in the keychain, and no server ever holds it. That is also the catch: if you lose the phone with no recovery set up, nobody can restore it for you."
        ),
        Answer(
            id: "recovery",
            question: "What happens if I lose my phone?",
            body: "If you turned on recovery, your key is sealed with your PIN and stored as ciphertext we cannot read. Sign in on a new phone, enter the PIN, and the wallet comes back. Without recovery there is no way back, so turn it on."
        ),
        Answer(
            id: "gas",
            question: "Do I need another token for fees?",
            body: "No. Arc charges fees in USDC, so the balance you hold is the balance you spend. Most chains make you keep a second token just to move the first one."
        ),
        Answer(
            id: "cheques",
            question: "What is a cheque here?",
            body: "A payment the other person collects when they choose to. Writing one costs nothing and moves nothing; it expires on its own, only the person you named can cash it even if it leaks, and you can void it any time before they do."
        ),
        Answer(
            id: "committed",
            question: "Why is my available amount lower than my balance?",
            body: "Because cheques you have written are still outstanding. Nothing on chain holds that money back, so the app does: what is available is your balance minus everything you have already promised."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                questions
                contact
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Questions worth\nasking about a wallet.")
                .font(.recourse(30, .bold))
                .foregroundStyle(RecourseColor.nightText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Answered here rather than buried in a policy nobody reads.")
                .font(.recourse(13, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
    }

    private var questions: some View {
        VStack(spacing: 0) {
            ForEach(Array(answers.enumerated()), id: \.element.id) { index, answer in
                row(answer)
                if index < answers.count - 1 {
                    Divider().overlay(RecourseColor.nightLine)
                }
            }
        }
    }

    private func row(_ answer: Answer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    expanded = expanded == answer.id ? nil : answer.id
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(answer.question)
                        .font(.recourse(14, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .rotationEffect(.degrees(expanded == answer.id ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded == answer.id {
                Text(answer.body)
                    .font(.recourse(12.5))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 16)
    }

    private var contact: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STILL STUCK")
                .font(.recourse(10, .semibold))
                .kerning(1.2)
                .foregroundStyle(RecourseColor.nightMuted)
            // One person builds this, so the honest thing is an email rather than a
            // support desk that implies a team behind it.
            Link(destination: URL(string: "mailto:hello@recourse.app")!) {
                HStack(spacing: 13) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                        .frame(width: 42, height: 42)
                        .background(RecourseColor.nightChip, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Email us")
                            .font(.recourse(14, .semibold))
                            .foregroundStyle(RecourseColor.nightText)
                        Text("A person reads these, usually same day")
                            .font(.recourse(11.5, .medium))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
