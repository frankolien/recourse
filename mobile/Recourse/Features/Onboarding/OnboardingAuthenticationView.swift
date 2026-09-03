import AuthenticationServices
import SwiftUI

private struct StoryItem: Identifiable {
    enum Icon {
        /// The thing itself, when it has a mark of its own.
        case usdc
        /// An app-icon style tile: one colour, one white glyph.
        case tile(Color, String)
    }

    let id: Int
    let title: String
    let icon: Icon
}

/// The carousel's icon, at the size the active row wants.
///
/// A tinted SF Symbol says what a thing is called; a coloured tile says what it is at a
/// glance, the way a home screen does. "Hold" gets the USDC coin because that is what
/// you hold, and the rest get a colour each so the set reads as four things rather than
/// four green glyphs.
private struct StoryIcon: View {
    let icon: StoryItem.Icon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .usdc:
            Image("USDCMark")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        case .tile(let color, let symbol):
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        }
    }
}

/// The whole way in, on one screen.
///
/// There used to be two: this one sold the product and offered "Create account" or "I
/// already have an account", and a second one asked how. That question was never worth
/// a screen. Apple and Google both sign in and sign up with the same tap, and the
/// passkey works out which ceremony it needs from the server's answer, so nobody has to
/// declare whether they are new before they are allowed to start.
struct OnboardingAuthenticationView: View {
    let accountSession: AccountSession
    let onBack: () -> Void
    let onAuthenticated: () -> Void

    @State private var activeIndex = 1
    @State private var showsPasskeyPrompt = false
    @State private var passkeyEmail = ""

    // What the app does, in the order someone meets it.
    private let items = [
        StoryItem(id: 0, title: "Hold", icon: .usdc),
        StoryItem(id: 1, title: "Send", icon: .tile(RecourseColor.ledger, "paperplane.fill")),
        StoryItem(id: 2, title: "Request", icon: .tile(Color(red: 0.94, green: 0.46, blue: 0.23), "arrow.down.left")),
        StoryItem(id: 3, title: "Earn", icon: .tile(Color(red: 0.55, green: 0.36, blue: 0.96), "chart.bar.fill"))
    ]

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            VStack(spacing: 0) {
                carousel(compact: compact)
                    .frame(height: proxy.size.height * (compact ? 0.34 : 0.38))

                hero(compact: compact)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                RecourseAnimatedStoryBackground()
                    .ignoresSafeArea()
            }
        }
        .task {
            await accountSession.prepareAppleSignIn()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.45))
                withAnimation(.smooth(duration: 0.55)) {
                    activeIndex = (activeIndex + 1) % items.count
                }
            }
        }
        .onChange(of: accountSession.account) { _, account in
            guard account != nil else { return }
            onAuthenticated()
        }
        .sheet(isPresented: $showsPasskeyPrompt) {
            passkeyPrompt
                .presentationDetents([.height(300)])
                .presentationBackground(RecourseColor.canvas)
        }
    }

    // MARK: Carousel

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
                .accessibilityLabel("Back")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: compact ? 8 : 11) {
                ForEach(items) { item in
                    let isActive = item.id == activeIndex

                    HStack(spacing: 13) {
                        if isActive {
                            StoryIcon(icon: item.icon, size: compact ? 34 : 40)
                                .transition(.move(edge: .leading).combined(with: .opacity).combined(with: .scale))
                        }

                        Text(item.title)
                            .font(.system(size: isActive ? (compact ? 32 : 38) : (compact ? 22 : 26), weight: .semibold))
                            .foregroundStyle(isActive ? RecourseColor.ink : RecourseColor.ink.opacity(0.14))
                    }
                    .frame(height: compact ? 42 : 48, alignment: .leading)
                    .animation(.smooth(duration: 0.55), value: activeIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 40)
            .padding(.bottom, 4)
        }
        .accessibilityHidden(true)
    }

    // MARK: Hero and the ways in

    private func hero(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 13) {
            // The screen's slack lives here, above the copy, where it joins the space
            // under the close button and reads as header room. Put it between the copy
            // and the buttons instead and it reads as a hole.
            Spacer(minLength: 0)

            // The mark, not a strapline. This is the screen that introduces the app,
            // and the one thing a strapline could add here is a sentence between the
            // logo and the promise underneath it.
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(height: compact ? 32 : 38)
                .accessibilityLabel("Recourse")
                .padding(.bottom, 4)

            Text("Your dollars,\non your phone.")
                .font(RecourseTypography.display(size: compact ? 25 : 28))
                .foregroundStyle(RecourseColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Pay anyone by name. Fees come out in dollars too, so there is no second token to keep.")
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            appleButton
                .padding(.top, compact ? 14 : 22)
            googleButton
            passkeyButton

            if let errorMessage = accountSession.errorMessage {
                Text(errorMessage)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.ledger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Ink rather than the muted grey: this line sits on the green bloom at the
            // bottom of the background, where muted grey falls to about the contrast of
            // a watermark.
            Text("By continuing, you agree to the Terms and Privacy Policy.")
                .font(.recourse(9, .medium))
                .foregroundStyle(RecourseColor.ink.opacity(0.62))
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, compact ? 12 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .disabled(accountSession.isAuthenticating)
        .overlay {
            if accountSession.isAuthenticating {
                ProgressView()
                    .tint(RecourseColor.ledger)
                    .padding(14)
                    .background(RecourseColor.surface, in: Circle())
            }
        }
    }

    private var appleButton: some View {
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
        // The system button scales its label with height, landing larger than every
        // other CTA; this cover redraws Apple's branding at the app's type scale.
        // Ready: taps fall through to the real control. Not ready (the backend nonce
        // has not arrived): the cover stays fully opaque, because dimming a UIKit
        // backed control and a SwiftUI overlay dims them separately and Apple's label
        // ghosts through, and tapping it retries the challenge fetch instead of leaving
        // the button dead until the screen reappears.
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
    }

    private var googleButton: some View {
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
    }

    private var passkeyButton: some View {
        Button {
            showsPasskeyPrompt = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Continue with passkey")
                    .font(.recourse(15, .semibold))
            }
            .foregroundStyle(RecourseColor.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RecourseColor.surface, in: Capsule())
            .overlay {
                Capsule().stroke(RecourseColor.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
                .font(.recourse(15, .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color.black, in: Capsule())
    }

    /// The email step, which exists because the server looks an account up by one
    /// before it can offer a challenge.
    private var passkeyPrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Continue with passkey")
                    .font(RecourseTypography.display(size: 24))
                    .foregroundStyle(RecourseColor.ink)
                Text("Your email names the account. Face ID does the rest, and there is no password to lose.")
                    .font(.recourse(13))
                    .foregroundStyle(RecourseColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("you@example.com", text: $passkeyEmail)
                .font(.recourse(15, .medium))
                .foregroundStyle(RecourseColor.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .submitLabel(.continue)
                .onSubmit { startPasskey() }
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(RecourseColor.surface, in: Capsule())
                .overlay { Capsule().stroke(RecourseColor.line, lineWidth: 1) }

            Button(action: startPasskey) {
                Text("Continue")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startPasskey() {
        let email = passkeyEmail
        showsPasskeyPrompt = false
        Task {
            // Dismissed first: the system passkey sheet cannot present over ours.
            try? await Task.sleep(for: .milliseconds(320))
            await accountSession.continueWithPasskey(email: email)
        }
    }
}

#if DEBUG
#Preview("Authentication") {
    OnboardingAuthenticationView(
        accountSession: .preview(),
        onBack: {},
        onAuthenticated: {}
    )
}
#endif
