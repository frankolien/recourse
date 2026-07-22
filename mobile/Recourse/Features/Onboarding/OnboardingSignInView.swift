import AuthenticationServices
import SwiftUI

enum OnboardingAuthenticationMode {
    case signUp
    case signIn

    var eyebrow: String {
        switch self {
        case .signUp: "CREATE YOUR ACCOUNT"
        case .signIn: "WELCOME BACK"
        }
    }

    var title: String {
        switch self {
        case .signUp: "Start with an account, not a wallet."
        case .signIn: "Sign in to your protected payments."
        }
    }

    var subtitle: String {
        switch self {
        case .signUp: "Recourse creates the testnet wallet quietly after setup."
        case .signIn: "Use the same account that holds your receipts and payment history."
        }
    }
}

private struct StoryItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
}

struct OnboardingSignupStoryView: View {
    let onBack: () -> Void
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void

    private let items = [
        StoryItem(id: 0, title: "Pay", icon: "creditcard.fill"),
        StoryItem(id: 1, title: "Protect", icon: "shield.checkered"),
        StoryItem(id: 2, title: "Verify", icon: "checkmark.seal.fill"),
        StoryItem(id: 3, title: "Resolve", icon: "checkmark.message.fill")
    ]

    @State private var activeIndex = 1
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            VStack(spacing: 0) {
                carousel(compact: compact)
                    .frame(height: proxy.size.height * (compact ? 0.42 : 0.46))

                storyHero
                    .frame(maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                RecourseAnimatedStoryBackground()
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                hasAppeared = true
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.45))
                withAnimation(.smooth(duration: 0.55)) {
                    activeIndex = (activeIndex + 1) % items.count
                }
            }
        }
    }

    private func carousel(compact: Bool) -> some View {
        ZStack(alignment: .top) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(RecourseColor.ink)
                        .frame(width: 44, height: 44)
                        .background(RecourseColor.surface, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                //Label("Recourse", systemImage: "shield.checkered")
                    //.font(.system(size: 16, weight: .bold))
                    //.foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                ForEach(items) { item in
                    let isActive = item.id == activeIndex

                    HStack(spacing: 13) {
                        if isActive {
                            Image(systemName: item.icon)
                                .font(.system(size: compact ? 21 : 25, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30)
                                .transition(.move(edge: .leading).combined(with: .opacity).combined(with: .scale))
                        }

                        Text(item.title)
                            .font(.system(size: isActive ? (compact ? 34 : 40) : (compact ? 23 : 27), weight: .semibold))
                            .foregroundStyle(isActive ? .white : .white.opacity(0.17))
                    }
                    .frame(height: compact ? 43 : 50, alignment: .leading)
                    .animation(.smooth(duration: 0.55), value: activeIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.top, 48)
        }
        .offset(y: hasAppeared ? 0 : 20)
        .opacity(hasAppeared ? 1 : 0)
    }

    private var storyHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 40)

            /*Image(systemName: "shield.checkered")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(RecourseColor.ledgerDeep)
                .frame(width: 48, height: 48)
                .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))*/

            Label("BUYER PROTECTION FOR USDC", systemImage: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)

            Text("Your payments,\nupgraded with proof.")
                .font(RecourseTypography.display(size: 31))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Clear terms before payment. Verifiable outcomes\nafter it.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button(action: onCreateAccount) {
                Text("Create Recourse account")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RecourseColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(RecourseColor.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            
            
            Button("I already have an account", action: onSignIn)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay {
                    Capsule().stroke(.white, lineWidth: 1)
                }
                .buttonStyle(.plain)

            Spacer(minLength: 4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct RecourseAnimatedStoryBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black

            Circle()
                .fill(Color(red: 0.38, green: 0.68, blue: 0.31))
                .frame(width: 620, height: 620)
                .blur(radius: 105)
                .offset(x: animate ? -90 : 90, y: animate ? -330 : -220)

            Circle()
                .fill(RecourseColor.ledger)
                .frame(width: 430, height: 430)
                .blur(radius: 120)
                .offset(x: animate ? 130 : -100, y: animate ? -60 : -150)
        }
        .drawingGroup()
        .onAppear {
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct OnboardingSignInView: View {
    let mode: OnboardingAuthenticationMode
    let accountSession: AccountSession
    let onBack: () -> Void
    let onAuthenticated: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760
            let heroHeight = proxy.size.height * (compact ? 0.34 : 0.39)

            VStack(spacing: 0) {
                authenticationHero(width: proxy.size.width, height: heroHeight)
                authenticationSheet(compact: compact)
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
        .task {
            await accountSession.prepareAppleSignIn()
        }
        .onChange(of: accountSession.account) { _, account in
            guard account != nil else { return }
            onAuthenticated()
        }
    }

    private func authenticationHero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Image("AccountEntryHero")
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
                Label("SECURE TESTNET", systemImage: "lock.fill")
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

    private func authenticationSheet(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode.eyebrow)
                    .recourseEyebrow()
                Text(mode.title)
                    .font(RecourseTypography.display(size: compact ? 29 : 33))
                    .foregroundStyle(RecourseColor.ink)
                    .lineLimit(2)
                Text(mode.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(RecourseColor.muted)
                    .lineLimit(2)
            }

            SignInWithAppleButton(
                .continue,
                onRequest: accountSession.configureAppleRequest,
                onCompletion: accountSession.handleAppleAuthorization
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 56)
            .clipShape(Capsule())
            .allowsHitTesting(accountSession.isAppleSignInReady)
            .opacity(accountSession.isAppleSignInReady ? 1 : 0.55)

            HStack(spacing: 12) {
                Image("GoogleG")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("Google sign-in coming next")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(RecourseColor.muted)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RecourseColor.surface, in: Capsule())
            .overlay {
                Capsule().stroke(RecourseColor.line, lineWidth: 1)
            }

            HStack(spacing: 10) {
                authenticationOption("Email", icon: "envelope")
                authenticationOption("Passkey", icon: "person.badge.key")
            }

            if let errorMessage = accountSession.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 4)

            HStack(spacing: 9) {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(RecourseColor.ledger)
                Text("Your signing key is created after authentication and stays on this iPhone.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
            }

            Text("By continuing, you agree to the Terms and Privacy Policy.")
                .font(.system(size: 9))
                .foregroundStyle(RecourseColor.muted)
        }
        .padding(.horizontal, 22)
        .padding(.top, compact ? 14 : 18)
        .padding(.bottom, compact ? 10 : 16)
        .frame(maxHeight: .infinity)
        .disabled(accountSession.isAuthenticating)
        .overlay {
            if accountSession.isAuthenticating {
                ProgressView()
                    .tint(RecourseColor.ledger)
                    .padding(14)
                    .background(RecourseColor.surface, in: Circle())
            }
        }
        .offset(y: hasAppeared ? 0 : 22)
        .opacity(hasAppeared ? 1 : 0)
    }

    private func authenticationOption(_ title: String, icon: String) -> some View {
        Button(action: {}) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RecourseColor.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RecourseColor.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(RecourseColor.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(true)
    }
}

#Preview("Animated signup story") {
    OnboardingSignupStoryView(
        onBack: {},
        onCreateAccount: {},
        onSignIn: {}
    )
}

#Preview("Authentication") {
    OnboardingSignInView(
        mode: .signIn,
        accountSession: AccountSession(),
        onBack: {},
        onAuthenticated: {}
    )
}
