import SwiftUI

/// Slow drifting motes over a settled hero band.
///
/// The clip's reveal runs once and then holds, so this is what keeps the band
/// alive afterwards. Drawing the ambience instead of looping footage is what
/// removes the tell: a looped clip restarts on a fixed period and the eye finds
/// it within a couple of passes. Here every mote carries its own drift and
/// twinkle frequency, none of them divide evenly, so the field never repeats.
struct HeroAmbientMotes: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let motes: [Mote] = {
        var rng = SeededGenerator(seed: 0x5EED_1234_ABCD_0001)
        return (0..<54).map { _ in
            Mote(
                x: Double.random(in: 0...1, using: &rng),
                y: Double.random(in: 0...1, using: &rng),
                radius: Double.random(in: 0.7...2.4, using: &rng),
                drift: Double.random(in: 0.010...0.045, using: &rng),
                twinkle: Double.random(in: 0.35...1.40, using: &rng),
                phase: Double.random(in: 0...(.pi * 2), using: &rng),
                warmth: Double.random(in: 0...1, using: &rng)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                for mote in motes {
                    var y = mote.y - t * mote.drift
                    y -= floor(y)

                    let alpha = mote.alpha(at: t, y: y)
                    guard alpha > 0.012 else { continue }

                    let center = CGPoint(x: mote.x * size.width, y: y * size.height)
                    let color = mote.color

                    // Halo first, then the core: two flat circles read as a lit
                    // point without a blur filter, which would cost an offscreen
                    // pass on every frame.
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - mote.radius * 3,
                            y: center.y - mote.radius * 3,
                            width: mote.radius * 6,
                            height: mote.radius * 6
                        )),
                        with: .color(color.opacity(alpha * 0.16))
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - mote.radius,
                            y: center.y - mote.radius,
                            width: mote.radius * 2,
                            height: mote.radius * 2
                        )),
                        with: .color(color.opacity(alpha))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Mote {
    let x: Double
    let y: Double
    let radius: Double
    let drift: Double
    let twinkle: Double
    let phase: Double
    let warmth: Double

    var color: Color {
        // Between the clip's cream bokeh and a cooler white, so the drawn motes
        // sit in the same family as the ones baked into the footage.
        Color(red: 1.0, green: 0.99 - 0.03 * warmth, blue: 0.94 - 0.10 * warmth)
    }

    /// Twinkle, faded out at both edges of the band so a mote recycling from top
    /// to bottom never pops into view.
    func alpha(at t: Double, y: Double) -> Double {
        let twinkled = 0.45 + 0.55 * sin(t * twinkle + phase)
        let edge = min(min(y, 1 - y) / 0.12, 1)
        return max(0, twinkled) * edge * 0.58
    }
}

/// xorshift64. Fixed seed keeps the field identical across redraws and launches,
/// so the composition is something we chose rather than something that varies.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
