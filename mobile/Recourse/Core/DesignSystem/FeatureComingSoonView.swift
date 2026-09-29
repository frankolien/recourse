import SwiftUI

/// What a feature shows on a chain that cannot support it yet.
///
/// Recourse runs on more than one chain and they do not carry the same things. Arc
/// testnet has a currency pool and a settlement vault; Arc mainnet has neither, because
/// Circle publishes no EURC there and the vault needs a USYC whitelist that does not
/// travel. A build points at one chain, so a feature is either real on that chain or it
/// is not, and the difference is a fact in the deployment file rather than a flag
/// someone remembers to set.
///
/// The card stays on Home either way. Someone who came looking for euros or for yield
/// should learn it is coming, not conclude the app has no answer. And it says which
/// thing is missing, because "coming soon" alone invites the question it is trying to
/// close.
struct FeatureComingSoonView: View {
    let icon: String
    let title: String
    let heading: String
    let explanation: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(width: 64, height: 64)
                    .background(RecourseColor.nightChip, in: Circle())

                VStack(spacing: 10) {
                    Text(heading)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(RecourseColor.nightText)

                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(RecourseColor.nightMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 0)

            Text("Everything else in the app works today.")
                .font(.footnote)
                .foregroundStyle(RecourseColor.nightMuted)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecourseColor.night)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Convert, where the chain has no venue deep enough to quote a fair rate.
    static var convert: FeatureComingSoonView {
        FeatureComingSoonView(
            icon: "arrow.left.arrow.right",
            title: "Convert",
            heading: "Euros are coming",
            explanation: "You will be able to hold euros beside your dollars and move between them at a fair rate. It is not open yet, because the only place to convert on this network is too small to give you one."
        )
    }

    /// Earn, where the chain has no settlement vault to put idle dollars into.
    static var earn: FeatureComingSoonView {
        FeatureComingSoonView(
            icon: "chart.bar.fill",
            title: "Earn",
            heading: "Yield is coming",
            explanation: "Your idle dollars will earn while they wait, in a US Treasury fund held by Circle. It is not open on this network yet, because the fund has to admit this account before a single dollar can go in."
        )
    }
}

#Preview("Convert") { NavigationStack { FeatureComingSoonView.convert } }
#Preview("Earn") { NavigationStack { FeatureComingSoonView.earn } }
