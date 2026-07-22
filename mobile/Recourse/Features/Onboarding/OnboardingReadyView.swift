import SwiftUI

struct OnboardingReadyView: View {
    let role: OnboardingRole
    let onComplete: () -> Void

    @State private var hasAppeared = false
    @State private var symbolBounce = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760
            let heroHeight = proxy.size.height * (compact ? 0.40 : 0.46)

            VStack(spacing: 0) {
                hero(width: proxy.size.width, height: heroHeight)
                readySheet(compact: compact)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
        .background(RecourseColor.canvas)
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                hasAppeared = true
            }
            symbolBounce.toggle()
        }
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Image("OnboardingPayment")
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height, alignment: .trailing)
                .clipped()
                .scaleEffect(hasAppeared ? 1 : 1.05)

            HStack {
                Label("Recourse", systemImage: "shield.checkered")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(height: 46)
                    .recourseGlassCapsule()
                Spacer()
                Text("READY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(height: 46)
                    .recourseGlassCapsule()
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)

            receipt
                .padding(.horizontal, 28)
                .frame(width: width, height: height, alignment: .bottom)
                .offset(y: hasAppeared ? 28 : 70)
                .scaleEffect(hasAppeared ? 1 : 0.9)
        }
    }

    private var receipt: some View {
        VStack(spacing: 11) {
            HStack {
                Label("PROTECTED", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(RecourseColor.ledger)
                Spacer()
                Text("ARC TESTNET")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RecourseColor.muted)
            }

            HStack(alignment: .lastTextBaseline) {
                Text("$24.00")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(RecourseColor.ink)
                Text("USDC")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RecourseColor.muted)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(RecourseColor.ledger)
                    .symbolEffect(.bounce, value: symbolBounce)
            }

            HStack {
                Text("CloudCompute")
                Spacer()
                Text("Terms locked")
                    .foregroundStyle(RecourseColor.ledger)
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(17)
        .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func readySheet(compact: Bool) -> some View {
        VStack(spacing: compact ? 12 : 16) {
            Spacer(minLength: compact ? 28 : 42)

            VStack(spacing: 8) {
                Text("Your \(role.rawValue.lowercased()) workspace is ready.")
                    .font(RecourseTypography.display(size: compact ? 31 : 36))
                    .foregroundStyle(RecourseColor.ink)
                    .multilineTextAlignment(.center)
                Text("Review the terms, approve the payment, and keep a receipt that can prove its own outcome.")
                    .font(.system(size: 14))
                    .foregroundStyle(RecourseColor.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            HStack(spacing: 18) {
                readyPoint("faceid", "Face ID")
                readyPoint("network", "Live on Arc")
                readyPoint("doc.text", "Proof saved")
            }

            Spacer(minLength: 4)

            Button("Open Recourse", action: onComplete)
                .buttonStyle(RecoursePrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.bottom, compact ? 10 : 18)
        .frame(maxHeight: .infinity)
        .opacity(hasAppeared ? 1 : 0)
    }

    private func readyPoint(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.ink)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Ready") {
    OnboardingReadyView(role: .buyer, onComplete: {})
}
