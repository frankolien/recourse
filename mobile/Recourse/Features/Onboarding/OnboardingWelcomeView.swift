import SwiftUI

struct OnboardingWelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    hero(
                        width: proxy.size.width,
                        height: proxy.size.height * (compact ? 0.42 : 0.50)
                    )
                    content(compact: compact)
                }

                actions(bottomInset: proxy.safeAreaInsets.bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .background(RecourseColor.canvas)
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // The clip carries its own entrance, so no scale-in here; two
            // overlapping reveals read as a stutter.
            OnboardingHeroVideo(fallback: .welcome)
                .frame(width: width, height: height)

            HStack {
                Label("Recourse", systemImage: "shield.checkered")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .recourseGlassCapsule()

                Spacer()

                HStack(spacing: 8) {
                    Image("ArcMark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 13)
                        // The chip sits on photo glass with white text, so force
                        // the on-dark (white) Arc mark even though onboarding is light.
                        .environment(\.colorScheme, .dark)
                    Text("ARC TESTNET")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .recourseGlassCapsule()
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text("Pay with confidence.")
                    .font(.recourse(16, .semibold))
                Text("Know the terms before money moves.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(24)
            .frame(height: height)

        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34))
    }

    private func content(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                Text("Payments should come\nwith protection.")
                    .font(RecourseTypography.display(size: compact ? 28 : 32))
                    .foregroundStyle(RecourseColor.ink)
                    .lineSpacing(-1)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Clear refund terms, verifiable outcomes, and no wallet complexity up front.")
                    .font(.system(size: compact ? 13 : 14))
                    .foregroundStyle(RecourseColor.muted)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                spacing: 12
            ) {
                trustItem(icon: "doc.text", label: "Terms first")
                trustItem(icon: "checkmark.shield", label: "Proof onchain")
                trustItem(icon: "bolt", label: "Fast settlement")
            }

            Spacer(minLength: compact ? 4 : 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, compact ? 16 : 20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func actions(bottomInset: CGFloat) -> some View {
        VStack(spacing: 9) {
            Button("Get protected", action: onGetStarted)
                .buttonStyle(RecoursePrimaryButtonStyle())

            Button("I already have an account", action: onSignIn)
                .buttonStyle(RecourseSecondaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, max(bottomInset, 34))
        .background(RecourseColor.canvas)
    }

    private func trustItem(icon: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RecourseColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Welcome") {
    OnboardingWelcomeView(
        onGetStarted: {},
        onSignIn: {}
    )
}
#endif
