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
                        .overlay {
                            Circle().stroke(RecourseColor.line, lineWidth: 1)
                        }
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
                                .font(.system(size: compact ? 18 : 21, weight: .semibold))
                                .foregroundStyle(RecourseColor.ledger)
                                .frame(width: 30)
                                .transition(.move(edge: .leading).combined(with: .opacity).combined(with: .scale))
                        }

                        Text(item.title)
                            .font(.system(size: isActive ? (compact ? 29 : 34) : (compact ? 20 : 23), weight: .semibold))
                            .foregroundStyle(isActive ? RecourseColor.ink : RecourseColor.ink.opacity(0.14))
                    }
                    .frame(height: compact ? 38 : 44, alignment: .leading)
                    .animation(.smooth(duration: 0.55), value: activeIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 40)
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
                .foregroundStyle(RecourseColor.ledger)

            Text("Your payments,\nupgraded with proof.")
                .font(RecourseTypography.display(size: 28))
                .foregroundStyle(RecourseColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Clear terms before payment. Verifiable outcomes\nafter it.")
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button(action: onCreateAccount) {
                Text("Create Recourse account")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RecourseColor.ledger, in: Capsule())
                    .shadow(color: RecourseColor.ledger.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            Button("I already have an account", action: onSignIn)
                .font(.recourse(14, .semibold))
                .foregroundStyle(RecourseColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule().stroke(RecourseColor.ledger.opacity(0.28), lineWidth: 1)
                }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .offset(y: hasAppeared ? 0 : 18)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.7).delay(0.15), value: hasAppeared)
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

    private func appleButtonCover(showsProgress: Bool) -> some View {
        HStack(spacing: 9) {
            if showsProgress {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .medium))
            }
            Text("Continue with Apple")
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(.black, in: Capsule())
    }

    private func authenticationHero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            OnboardingHeroArt(variant: .account)
                .frame(width: width, height: height)
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
                    .frame(height: 44)
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
                    .fixedSize(horizontal: false, vertical: true)
                Text(mode.subtitle)
                    .font(.recourse(14))
                    .foregroundStyle(RecourseColor.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SignInWithAppleButton(
                .continue,
                onRequest: accountSession.configureAppleRequest,
                onCompletion: accountSession.handleAppleAuthorization
            )
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: 375)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .clipShape(Capsule())
            // The system button scales its label with height, landing larger
            // than every other CTA; this cover redraws Apple's branding at the
            // app's type scale. Ready: taps fall through to the real control.
            // Not ready (the backend nonce hasn't arrived): the cover stays
            // fully opaque, because dimming a UIKit-backed control and a
            // SwiftUI overlay dims them separately and Apple's label ghosts
            // through, and tapping it retries the challenge fetch instead of
            // leaving the button dead until the screen reappears.
            .overlay {
                if accountSession.isAppleSignInReady {
                    appleButtonCover(showsProgress: false)
                        .allowsHitTesting(false)
                } else {
                    Button {
                        Task { await accountSession.prepareAppleSignIn() }
                    } label: {
                        appleButtonCover(showsProgress: accountSession.isPreparingAppleSignIn)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task {
                    await accountSession.signInWithGoogle(
                        clientID: AppConfiguration.googleIOSClientID
                    )
                }
            } label: {
                HStack(spacing: 12) {
                    Image("GoogleG")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("Continue with Google")
                        .font(.recourse(15, .semibold))
                        .foregroundStyle(RecourseColor.ink)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RecourseColor.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(RecourseColor.line, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                authenticationOption("Email", icon: "envelope")
                authenticationOption("Passkey", icon: "person.badge.key")
            }

            if let errorMessage = accountSession.errorMessage {
                Text(errorMessage)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.ledger)
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
                .font(.recourse(9))
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

#if DEBUG
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
        accountSession: .preview(),
        onBack: {},
        onAuthenticated: {}
    )
}
#endif
