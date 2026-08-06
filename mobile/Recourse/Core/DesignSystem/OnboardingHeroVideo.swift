import AVFoundation
import SwiftUI

/// The logo reveal playing as the hero band on the first onboarding screen.
///
/// The clip is composed for a full 9:16 frame, but the band is far wider than it
/// is tall. Filling the band would scale the mark up to most of its height, so
/// the clip is fitted instead and a second copy, cropped hard and blurred past
/// recognition, carries the margin either side. The bokeh then runs edge to edge
/// with no seam and the mark stays the size it was drawn to be.
///
/// Plays once and holds the final frame rather than looping: the reveal is an
/// entrance, and a loop would tug the eye back every three seconds while someone
/// is reading the copy underneath. Falls back to the drawn hero whenever the clip
/// should not or cannot play, so the band is never left empty.
struct OnboardingHeroVideo: View {
    /// Drawn hero to show instead when motion is reduced or the clip is missing.
    let fallback: OnboardingHeroArt.Variant

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fillPlayer: AVPlayer?
    @State private var markPlayer: AVPlayer?

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

                    if let fillPlayer {
                        HeroPlayerLayer(player: fillPlayer, gravity: .resizeAspectFill)
                            // Overfilled so the blur's soft edge falls outside
                            // the band instead of thinning against it.
                            .scaleEffect(1.18)
                            .blur(radius: 30)
                            .overlay(Color.black.opacity(0.18))
                    }

                    if let markPlayer {
                        HeroPlayerLayer(player: markPlayer, gravity: .resizeAspect)
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
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onAppear { start() }
            .onDisappear {
                fillPlayer?.pause()
                markPlayer?.pause()
            }
        }
    }

    private func start() {
        guard let url = Self.clip else { return }
        if fillPlayer == nil {
            // One AVPlayer drives one AVPlayerLayer, so the two layers need two
            // players. They start together and the fill is unrecognisable, which
            // leaves any drift over three seconds invisible.
            fillPlayer = makePlayer(url)
            markPlayer = makePlayer(url)
        }
        for player in [fillPlayer, markPlayer].compactMap({ $0 }) {
            player.seek(to: .zero)
            player.play()
        }
    }

    private func makePlayer(_ url: URL) -> AVPlayer {
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
