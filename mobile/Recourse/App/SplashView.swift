import SwiftUI

/// Boot sequence in two beats: the bare R glyph holds the stage exactly where
/// the static launch image left it, then slides away as the wordmark sweeps in
/// to the right, its R being the logo glyph itself rather than a typed letter.
/// The green aurora blooms in underneath rather than starting visible so the
/// first SwiftUI frame still matches the plain white launch image.
struct SplashView: View {
    @State private var auroraIn = false
    @State private var wordmarkIn = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            RecourseAnimatedStoryBackground()
                .ignoresSafeArea()
                .opacity(auroraIn ? 1 : 0)

            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(height: 96)
                .opacity(wordmarkIn ? 0 : 1)
                .offset(x: wordmarkIn ? -118 : 0)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)

                Text("ecourse")
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-1.2)
                    .foregroundStyle(RecourseColor.ledger)
            }
            .opacity(wordmarkIn ? 1 : 0)
            .offset(x: wordmarkIn ? 0 : 26)
            .mask(alignment: .leading) {
                Rectangle()
                    .frame(width: wordmarkIn ? 260 : 0, height: 72)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                auroraIn = true
            }
            withAnimation(.easeInOut(duration: 0.6).delay(1.0)) {
                wordmarkIn = true
            }
        }
    }
}

#if DEBUG
#Preview {
    SplashView()
}
#endif
