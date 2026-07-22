import SwiftUI

struct OnboardingWelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    @State private var hasAppeared = false
    @State private var pulse = false

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
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                hasAppeared = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Image("OnboardingPayment")
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height, alignment: .trailing)
                .clipped()
                .scaleEffect(hasAppeared ? 1 : 1.06)

            Rectangle()
                .fill(.black.opacity(0.16))
                .frame(height: height)

            HStack {
                Label("Recourse", systemImage: "shield.checkered")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 35)
                    .recourseGlassCapsule()

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 6)
                        .scaleEffect(pulse ? 1.25 : 0.85)
                    Text("ARC TESTNET")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 35)
                .recourseGlassCapsule()
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text("Pay with confidence.")
                    .font(.system(size: 16, weight: .semibold))
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
                    .font(RecourseTypography.display(size: compact ? 31 : 36))
                    .foregroundStyle(RecourseColor.ink)
                    .lineSpacing(-1)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Clear refund terms, verifiable outcomes, and no wallet complexity up front.")
                    .font(.system(size: compact ? 14 : 15))
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
        .offset(y: hasAppeared ? 0 : 24)
        .opacity(hasAppeared ? 1 : 0)
    }

    private func actions(bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            Button("Get protected", action: onGetStarted)
                .buttonStyle(RecoursePrimaryButtonStyle())

            Button("I already have an account", action: onSignIn)
                .buttonStyle(RecourseSecondaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, max(bottomInset, 34))
        .background(RecourseColor.canvas)
        .offset(y: hasAppeared ? 0 : 24)
        .opacity(hasAppeared ? 1 : 0)
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

#Preview("Welcome") {
    OnboardingWelcomeView(
        onGetStarted: {},
        onSignIn: {}
    )
}
