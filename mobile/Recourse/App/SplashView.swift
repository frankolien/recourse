import SwiftUI

/// Boot sequence in two beats: the bare R glyph holds the stage exactly where
/// the static launch image left it, then slides away as the full wordmark
/// sweeps in to the right.
struct SplashView: View {
    @State private var wordmarkIn = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(height: 96)
                .opacity(wordmarkIn ? 0 : 1)
                .offset(x: wordmarkIn ? -118 : 0)

            Text("Recourse")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-1.2)
                .foregroundStyle(RecourseColor.ledger)
                .opacity(wordmarkIn ? 1 : 0)
                .offset(x: wordmarkIn ? 0 : 26)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: wordmarkIn ? 260 : 0, height: 64)
                }
        }
        .onAppear {
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
