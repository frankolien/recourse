import SwiftUI

/// What Convert shows where the chain has no venue worth using.
///
/// A deployed venue and a usable one are different things. Arc testnet has a pool,
/// and its 200 bps sanity guard admits about 0.78 USDC against 44 USDC of depth;
/// nothing arbitrages a testnet, so the first trade leaves the price off by its own
/// impact and the next person is refused. Showing the real screen there would hand
/// whoever opened the app first a refusal they cannot act on.
///
/// The card stays on Home rather than disappearing, because someone who came for
/// euros should learn that they are coming, not conclude the app has no answer.
/// `Deployment.fxPublic` decides which screen they get, so a chain that gains a real
/// venue turns this off in the deployment file rather than in code.
struct ConvertComingSoonView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(width: 64, height: 64)
                    .background(RecourseColor.nightChip, in: Circle())

                VStack(spacing: 10) {
                    Text("Euros are coming")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(RecourseColor.nightText)

                    Text("You will be able to hold euros beside your dollars and move between them at a fair rate. It is not open yet, because the only place to convert on this network is too small to give you one.")
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
        .navigationTitle("Convert")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { ConvertComingSoonView() }
}
