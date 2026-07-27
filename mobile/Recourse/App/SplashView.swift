import SwiftUI

/// Branded boot screen. Takes over seamlessly from the static launch image
/// and stays alive with motion while the cached session restores, so even a
/// slow start never reads as a frozen logo.
struct SplashView: View {
    @State private var hasAppeared = false
    @State private var ripples = false

    var body: some View {
        ZStack {
            RecourseColor.canvas.ignoresSafeArea()

            rippleRing(delay: 0)
            rippleRing(delay: 0.55)

            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .scaleEffect(hasAppeared ? 1 : 0.9)
                .shadow(color: RecourseColor.ledger.opacity(hasAppeared ? 0.24 : 0), radius: 26, y: 12)

            VStack(spacing: 7) {
                Text("Recourse")
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundStyle(RecourseColor.ink)
                Text("Disputes are computed, not decided.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 126 : 142)

            VStack {
                Spacer()
                HStack(spacing: 7) {
                    Image("ArcMark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 12)
                    Text("LIVE ON ARC TESTNET")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(RecourseColor.muted)
                }
                .opacity(hasAppeared ? 1 : 0)
                .padding(.bottom, 26)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.05)) {
                hasAppeared = true
            }
            ripples = true
        }
    }

    private func rippleRing(delay: Double) -> some View {
        Circle()
            .stroke(RecourseColor.ledger.opacity(0.3), lineWidth: 1.5)
            .frame(width: 136, height: 136)
            .scaleEffect(ripples ? 2.5 : 0.95)
            .opacity(ripples ? 0 : 0.9)
            .animation(
                .easeOut(duration: 1.9).repeatForever(autoreverses: false).delay(delay),
                value: ripples
            )
    }
}

#if DEBUG
#Preview {
    SplashView()
}
#endif
