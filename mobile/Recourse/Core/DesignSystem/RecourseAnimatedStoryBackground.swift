import SwiftUI

/// White page with a live green aurora in the bottom-left corner, shared by the
/// splash screen and the sign-in story. A continuous clock (TimelineView) drives
/// each blob along its own slow orbit; the frequencies don't divide evenly, so
/// the composition never visibly repeats, like a live wallpaper, while the main
/// bloom breathes in scale and opacity. Freezes under Reduce Motion.
struct RecourseAnimatedStoryBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Color.white

                RadialGradient(
                    colors: [RecourseColor.ledger.opacity(0.15 + 0.04 * sin(t * 0.21)), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 430
                )

                // Main bloom: hugs the corner, orbiting on a slow ellipse and breathing.
                glow(RecourseColor.ledger, size: 620, core: 0.28)
                    .opacity(0.55 + 0.07 * sin(t * 0.17))
                    .scaleEffect(1 + 0.05 * sin(t * 0.13))
                    .offset(
                        x: -140 + 44 * sin(t * 0.27),
                        y: 415 + 30 * cos(t * 0.19)
                    )

                // Companion: brighter leaf green, swimming along the bottom edge.
                glow(Color(red: 0.38, green: 0.68, blue: 0.31), size: 410, core: 0.22)
                    .opacity(0.42 + 0.06 * cos(t * 0.23))
                    .offset(
                        x: -5 + 58 * sin(t * 0.16 + 2.1),
                        y: 450 + 24 * sin(t * 0.29 + 0.8)
                    )

                // Accent: a small bright wisp drifting wider, adds a third layer of depth.
                glow(Color(red: 0.55, green: 0.78, blue: 0.45), size: 260, core: 0.18)
                    .opacity(0.32 + 0.07 * sin(t * 0.31 + 1.2))
                    .offset(
                        x: -60 + 90 * sin(t * 0.11 + 4.0),
                        y: 480 + 18 * cos(t * 0.24 + 2.6)
                    )
            }
        }
    }

    // Soft bloom drawn as a radial falloff rather than Circle().blur(): a gradient
    // renders in-place, while blur + drawingGroup needs an offscreen Metal pass every
    // frame, the pass that dies on the Simulator with "invalid reuse after
    // initialization failure". Same glow, no offscreen rendering, cheaper everywhere.
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
