import AVFoundation
import SwiftUI

/// The logo reveal playing as the hero band across onboarding.
///
/// The reveal runs once per launch and then holds on its final frame; the band
/// stays alive afterwards on drawn motes rather than a looped clip. Replaying
/// the reveal every few seconds turns an entrance into a motif, and any looped
/// footage announces its own period after a pass or two. Screens reached later
/// in the flow open already settled, so the animation reads as the app arriving
/// rather than as decoration on every screen.
///
/// The clip is composed for a full 9:16 frame, but the band is far wider than it
/// is tall. Filling the band would scale the mark up to most of its height, so
/// the clip is fitted instead and a second copy, cropped hard and blurred past
/// recognition, carries the margin either side.
struct OnboardingHeroVideo: View {
    /// Drawn hero to show instead when motion is reduced or the clip is missing.
    let fallback: OnboardingHeroArt.Variant

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine: HeroClipEngine?
    @State private var ambientRevealed = false

    private static let clip = Bundle.main.url(forResource: "recourse-onboarding", withExtension: "mp4")
    private static let clipAspect: CGFloat = 1080.0 / 1920.0

    var body: some View {
        if reduceMotion || Self.clip == nil {
            OnboardingHeroArt(variant: fallback)
        } else {
            GeometryReader { proxy in
                // Width the fitted clip actually occupies, so the feather below
                // lands on its edges rather than somewhere in the band.
                let markWidth = min(proxy.size.height * Self.clipAspect, proxy.size.width)

                ZStack {
                    // The clip opens on near black. Matching it keeps the band
                    // from flashing pale before the first frame arrives.
                    Color(red: 0.043, green: 0.047, blue: 0.043)

                    if let engine {
                        HeroPlayerLayer(player: engine.fill, gravity: .resizeAspectFill)
                            // Overfilled so the blur's soft edge falls outside
                            // the band instead of thinning against it.
                            .scaleEffect(1.18)
                            .blur(radius: 30)
                            .overlay(Color.black.opacity(0.18))

                        HeroPlayerLayer(player: engine.mark, gravity: .resizeAspect)
                            .frame(width: markWidth, height: proxy.size.height)
                            // Without this the fitted clip meets the blurred
                            // fill on two hard vertical lines.
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 0.10),
                                        .init(color: .black, location: 0.90),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }

                    // Held back until the reveal lands: the clip carries its own
                    // particulate on the way in, and two fields at once is soup.
                    HeroAmbientMotes()
                        .blendMode(.plusLighter)
                        .opacity(ambientRevealed ? 1 : 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onAppear { start() }
            .onDisappear { engine?.pause() }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                revealAmbient(after: 0)
            }
        }
    }

    private func start() {
        guard let url = Self.clip else { return }
        if engine == nil {
            engine = HeroClipEngine(url: url)
        }

        if HeroReveal.hasPlayed {
            engine?.settle()
            ambientRevealed = true
        } else {
            HeroReveal.hasPlayed = true
            ambientRevealed = false
            engine?.play()
            // Backstop: the end-of-item notification is the precise cue, but a
            // stalled decode should not leave the band without its ambience.
            revealAmbient(after: 3.4)
        }
    }

    private func revealAmbient(after delay: TimeInterval) {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !ambientRevealed else { return }
            withAnimation(.easeIn(duration: 1.1)) { ambientRevealed = true }
        }
    }
}

/// Whether this launch has already shown the reveal. The animation is an
/// entrance for the app, not for each screen that happens to carry the band.
@MainActor
private enum HeroReveal {
    static var hasPlayed = false
}

/// Owns the two players behind a hero band. One AVPlayer drives one
/// AVPlayerLayer, so the fitted clip and the blurred fill need one each.
private final class HeroClipEngine {
    let fill: AVPlayer
    let mark: AVPlayer

    init(url: URL) {
        fill = HeroClipEngine.makePlayer(url)
        mark = HeroClipEngine.makePlayer(url)
    }

    func play() {
        for player in [fill, mark] {
            player.seek(to: .zero)
            player.play()
        }
    }

    func pause() {
        fill.pause()
        mark.pause()
    }

    /// Park both players on the final frame without playing through to it.
    func settle() {
        for player in [fill, mark] {
            player.pause()
            player.seek(to: .positiveInfinity, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private static func makePlayer(_ url: URL) -> AVPlayer {
        let player = AVPlayer(playerItem: AVPlayerItem(url: url))
        // The clip carries no audio track, but muting also keeps it from ever
        // interrupting whatever the user is already listening to.
        player.isMuted = true
        player.actionAtItemEnd = .pause
        return player
    }
}

private struct HeroPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = gravity
    }
}

/// Backing the view with AVPlayerLayer directly lets the layer track the view's
/// bounds on its own. A hand-managed sublayer needs its frame reset on every
/// size change, and misses the one that matters: the first layout pass.
private final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
