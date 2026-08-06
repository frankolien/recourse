import SwiftUI

/// Hero band behind the onboarding chrome. This replaces the stock photography
/// the first submission shipped with: those frames showed non-Apple handsets and
/// another vendor's wallet UI, which App Review rejects under guideline 2.3.10
/// (non-iOS device and status bar images inside the binary). Drawing the hero in
/// code means the flow cannot carry someone else's platform into a build again.
///
/// Deep ledger green ground so the white glass capsules and captions layered on
/// top keep their contrast, with the same living aurora language as the splash
/// and sign-in story. Blooms are radial falloffs rather than blurred circles for
/// the reason spelled out in RecourseAnimatedStoryBackground: a blur wants an
/// offscreen Metal pass that the Simulator intermittently fails to allocate.
struct OnboardingHeroArt: View {
    enum Variant {
        /// Welcome. Light gathers bottom-trailing, leaving the bottom-leading
        /// corner dark for the caption that sits there.
        case welcome
        /// Sign in and sign up. Corner bloom that rhymes with the white aurora
        /// on the story screen the user just came from.
        case account
        /// Ready. Centred bloom that reads as a glow behind the receipt card.
        case ready
    }

    let variant: Variant

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.008, green: 0.075, blue: 0.055),
                    Color(red: 0.020, green: 0.200, blue: 0.150)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ledgerRules

            GeometryReader { proxy in
                let span = min(proxy.size.width, proxy.size.height)

                // The mark sunk into the ground rather than set on top of it:
                // enough to make the band unmistakably ours, faint enough that
                // the chrome and captions never have to fight it.
                Image("LaunchMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: span * 0.50)
                    .foregroundStyle(.white.opacity(0.075))
                    .position(
                        x: proxy.size.width * mark.x,
                        y: proxy.size.height * mark.y
                    )
            }

            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let span = min(proxy.size.width, proxy.size.height)

                    ZStack {
                        ForEach(Array(blooms.enumerated()), id: \.offset) { _, bloom in
                            glow(bloom.color, size: span * bloom.scale, core: bloom.core)
                                .opacity(bloom.opacity + bloom.wobble * sin(t * bloom.speed + bloom.phase))
                                .position(
                                    x: proxy.size.width * bloom.x
                                        + bloom.drift * CGFloat(sin(t * bloom.speed * 0.63 + bloom.phase)),
                                    y: proxy.size.height * bloom.y
                                        + bloom.drift * 0.6 * CGFloat(cos(t * bloom.speed * 0.81 + bloom.phase))
                                )
                        }
                    }
                }
            }

            // The app bar and back button ride the top edge in white glass.
            LinearGradient(
                colors: [.black.opacity(0.30), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .clipped()
    }

    /// Receipt paper, faintly. The rules carry the one idea the whole product
    /// rests on, so they earn their place over a decorative texture.
    private var ledgerRules: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            var y = spacing
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                    with: .color(.white.opacity(0.045))
                )
                y += spacing
            }
        }
    }

    /// Centre of the sunken mark, placed away from each variant's brightest
    /// bloom so the two read as separate layers instead of one smear.
    private var mark: (x: CGFloat, y: CGFloat) {
        switch variant {
        case .welcome: (0.32, 0.48)
        case .account: (0.68, 0.52)
        case .ready: (0.50, 0.44)
        }
    }

    private var blooms: [Bloom] {
        switch variant {
        case .welcome:
            [
                Bloom(color: .emerald, x: 0.82, y: 0.78, scale: 1.90, core: 0.26,
                      opacity: 0.60, wobble: 0.07, speed: 0.17, phase: 0.0, drift: 34),
                Bloom(color: .leaf, x: 0.40, y: 0.98, scale: 1.20, core: 0.22,
                      opacity: 0.36, wobble: 0.06, speed: 0.23, phase: 2.1, drift: 42),
                Bloom(color: .wisp, x: 0.60, y: 0.22, scale: 0.70, core: 0.16,
                      opacity: 0.24, wobble: 0.06, speed: 0.31, phase: 1.2, drift: 50)
            ]
        case .account:
            [
                Bloom(color: .emerald, x: 0.10, y: 0.92, scale: 2.00, core: 0.27,
                      opacity: 0.62, wobble: 0.07, speed: 0.19, phase: 0.6, drift: 38),
                Bloom(color: .leaf, x: 0.54, y: 1.02, scale: 1.25, core: 0.22,
                      opacity: 0.38, wobble: 0.06, speed: 0.16, phase: 2.7, drift: 46),
                Bloom(color: .wisp, x: 0.88, y: 0.26, scale: 0.66, core: 0.16,
                      opacity: 0.22, wobble: 0.05, speed: 0.27, phase: 4.0, drift: 44)
            ]
        case .ready:
            [
                Bloom(color: .emerald, x: 0.50, y: 0.94, scale: 2.05, core: 0.28,
                      opacity: 0.64, wobble: 0.07, speed: 0.15, phase: 1.4, drift: 30),
                Bloom(color: .leaf, x: 0.18, y: 0.70, scale: 1.05, core: 0.20,
                      opacity: 0.32, wobble: 0.06, speed: 0.25, phase: 0.3, drift: 40),
                Bloom(color: .wisp, x: 0.86, y: 0.34, scale: 0.78, core: 0.17,
                      opacity: 0.26, wobble: 0.06, speed: 0.21, phase: 3.3, drift: 46)
            ]
        }
    }

    private func glow(_ color: Color, size: CGFloat, core: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: color, location: 0),
                        .init(color: color, location: core),
                        .init(color: color.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }
}

private struct Bloom {
    let color: Color
    /// Centre as a fraction of the band, so the art holds its composition across
    /// the different hero heights the three screens ask for.
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let core: CGFloat
    let opacity: Double
    let wobble: Double
    let speed: Double
    let phase: Double
    let drift: CGFloat
}

private extension Color {
    // Brighter than the ink-on-white ledger green: these have to carry over a
    // near-black ground rather than under it.
    static let emerald = Color(red: 0.05, green: 0.55, blue: 0.38)
    static let leaf = Color(red: 0.38, green: 0.68, blue: 0.31)
    static let wisp = Color(red: 0.60, green: 0.82, blue: 0.50)
}

#if DEBUG
#Preview("Hero art") {
    VStack(spacing: 0) {
        OnboardingHeroArt(variant: .welcome)
        OnboardingHeroArt(variant: .account)
        OnboardingHeroArt(variant: .ready)
    }
    .ignoresSafeArea()
}
#endif
