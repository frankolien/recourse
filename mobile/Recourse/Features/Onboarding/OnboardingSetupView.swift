import SwiftUI

enum OnboardingRole: String, CaseIterable {
    case buyer = "Buyer"
    case merchant = "Merchant"

    var detail: String {
        switch self {
        case .buyer: "Pay in USDC with terms and verifiable protection."
        case .merchant: "Accept protected payments and receive funds quickly."
        }
    }

    var icon: String {
        switch self {
        case .buyer: "person.crop.circle.fill"
        case .merchant: "storefront.fill"
        }
    }
}

struct OnboardingSetupView: View {
    let accountLabel: String
    let onBack: () -> Void
    let onContinue: (OnboardingRole) -> Void

    @State private var selectedRole: OnboardingRole = .buyer
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760
            let heroHeight = proxy.size.height * (compact ? 0.37 : 0.43)

            VStack(spacing: 0) {
                hero(width: proxy.size.width, height: heroHeight)
                roleSheet(compact: compact)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea(edges: .top)
        }
        .background(RecourseColor.canvas)
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                hasAppeared = true
            }
        }
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Image("BuyerSetupHero")
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .scaleEffect(hasAppeared ? 1 : 1.05)

            HStack {
                RecourseGlassIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back",
                    action: onBack
                )
                Spacer()
                Text("SIGNED IN")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(RecourseColor.ledgerDeep)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(RecourseColor.surface, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34))
    }

    private func roleSheet(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(accountLabel.uppercased())
                    .recourseEyebrow()
                Text("How will you use Recourse?")
                    .font(RecourseTypography.display(size: compact ? 29 : 33))
                    .foregroundStyle(RecourseColor.ink)
                Text("Choose your first workspace. You can add another role later.")
                    .font(.system(size: 14))
                    .foregroundStyle(RecourseColor.muted)
            }

            ForEach(OnboardingRole.allCases, id: \.self) { role in
                roleButton(role)
            }

            Spacer(minLength: 4)

            Button("Continue as \(selectedRole.rawValue)") {
                onContinue(selectedRole)
            }
            .buttonStyle(RecoursePrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, compact ? 14 : 18)
        .padding(.bottom, compact ? 10 : 18)
        .frame(maxHeight: .infinity)
        .offset(y: hasAppeared ? 0 : 22)
        .opacity(hasAppeared ? 1 : 0)
    }

    private func roleButton(_ role: OnboardingRole) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedRole = role
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: role.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selectedRole == role ? .white : RecourseColor.ledger)
                    .frame(width: 44, height: 44)
                    .background(
                        selectedRole == role ? RecourseColor.ledger : RecourseColor.mint,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(role.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                    Text(role.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(RecourseColor.muted)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: selectedRole == role ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedRole == role ? RecourseColor.ledger : RecourseColor.line)
            }
            .foregroundStyle(RecourseColor.ink)
            .padding(14)
            .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selectedRole == role ? RecourseColor.ledger : RecourseColor.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Role selection") {
    OnboardingSetupView(
        accountLabel: "FRANK@RECOURSE.APP",
        onBack: {},
        onContinue: { _ in }
    )
}
