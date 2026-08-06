#if DEBUG
import AuthenticationServices
import CryptoKit
import SwiftUI

/// Spike, not a feature. Answers the one question the wallet architecture note
/// hangs on: does the PRF extension actually return key material on this device,
/// and is that material stable across separate assertions?
///
/// If it is stable, a wallet key can be wrapped against a passkey and unwrapped
/// on any device the passkey reaches, with the server holding only ciphertext.
/// If it is not, the whole passkey path collapses back to recovery phrases.
///
/// Runs entirely on device. The challenge is random rather than server-issued,
/// because nothing here verifies a signature; only the PRF output matters.
struct PasskeyPRFProbeView: View {
    @State private var probe = PRFProbe()

    var body: some View {
        List {
            Section {
                Text("Registers a passkey for \(PRFProbe.relyingParty), then asserts twice with the same salt. PRF is usable only if both assertions return identical bytes.")
                    .font(.footnote)
                    .foregroundStyle(RecourseColor.nightMuted)
            }

            Section {
                Button("1. Register passkey with PRF") {
                    Task { await probe.register() }
                }
                Button("2. Assert twice, compare output") {
                    Task { await probe.assertTwice() }
                }
                .disabled(!probe.hasCredential)
                Button("Reset", role: .destructive) { probe.reset() }
            }

            Section("Result") {
                ForEach(probe.log) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.symbol)
                        Text(line.message)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if probe.log.isEmpty {
                    Text("Nothing run yet.")
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
        }
        .navigationTitle("Passkey PRF probe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
@Observable
final class PRFProbe: NSObject {
    struct Line: Identifiable {
        let id = UUID()
        let symbol: String
        let message: String
    }

    /// Must match a domain listed in the app's webcredentials entitlement and
    /// served by that domain's apple-app-site-association.
    static let relyingParty = "recourse-arc.vercel.app"

    /// Fixed so the two assertions ask the authenticator the same question. In
    /// production this would be a per-account salt, safe to store server side
    /// because it is not a secret.
    private static let salt = Data(SHA256.hash(data: Data("recourse-arc-wallet-v1".utf8)))

    private(set) var log: [Line] = []
    private(set) var hasCredential = false

    private var credentialID: Data?
    private var firstOutput: Data?
    private var continuation: CheckedContinuation<ASAuthorization, any Error>?

    func reset() {
        log = []
        credentialID = nil
        firstOutput = nil
        hasCredential = false
    }

    func register() async {
        guard #available(iOS 18.0, *) else {
            add("x", "PRF needs iOS 18. This device is older.")
            return
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: Self.relyingParty
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: Self.randomBytes(32),
            name: "PRF probe",
            userID: Self.randomBytes(16)
        )
        // Asks only whether PRF is available for this credential, which is what
        // registration is for. Salts come later, at assertion.
        request.prf = .checkForSupport

        do {
            let authorization = try await perform(request)
            guard let registration = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
                add("x", "Unexpected credential type back from registration.")
                return
            }

            credentialID = registration.credentialID
            hasCredential = true
            add("ok", "Registered. credentialID \(registration.credentialID.prefix(8).hexString)...")

            guard let prf = registration.prf else {
                add("x", "No PRF output object. The authenticator ignored the extension.")
                return
            }
            add(prf.isSupported ? "ok" : "x", "prf.isSupported = \(prf.isSupported)")
        } catch {
            add("x", describe(error))
        }
    }

    func assertTwice() async {
        firstOutput = nil
        for attempt in 1...2 {
            guard let output = await assertOnce(attempt: attempt) else { return }
            if let first = firstOutput {
                let stable = first == output
                add(stable ? "ok" : "x", stable
                    ? "Both assertions matched. PRF is deterministic here."
                    : "Outputs differed. PRF is not usable as key material.")
                if stable {
                    add("ok", "Derived wallet seed \(Self.deriveSeed(from: output).prefix(8).hexString)...")
                }
            } else {
                firstOutput = output
            }
        }
    }

    private func assertOnce(attempt: Int) async -> Data? {
        guard #available(iOS 18.0, *) else { return nil }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: Self.relyingParty
        )
        let request = provider.createCredentialAssertionRequest(challenge: Self.randomBytes(32))
        if let credentialID {
            request.allowedCredentials = [
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credentialID)
            ]
        }
        request.prf = .inputValues(
            .init(saltInput1: Self.salt, saltInput2: nil),
            perCredentialInputValues: nil
        )

        do {
            let authorization = try await perform(request)
            guard let assertion = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
                add("x", "Unexpected credential type back from assertion \(attempt).")
                return nil
            }
            // Swift refines the PRF output to a SymmetricKey rather than raw
            // bytes, which is the right shape: it is key material, not a value
            // to pass around. Unwrapped here only so the probe can compare runs.
            guard let outputKey = assertion.prf?.first else {
                add("x", "Assertion \(attempt) returned no PRF output.")
                return nil
            }
            let output = Data(outputKey.withUnsafeBytes { Array($0) })
            add("ok", "Assertion \(attempt): \(output.count) bytes, \(output.prefix(8).hexString)...")
            return output
        } catch {
            add("x", describe(error))
            return nil
        }
    }

    /// The bytes PRF hands back are key material, not a key. HKDF binds them to
    /// this purpose so the same credential could serve another one later without
    /// the two sharing a secret.
    private static func deriveSeed(from prfOutput: Data) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: prfOutput),
            info: Data("recourse-arc-wallet-v1".utf8),
            outputByteCount: 32
        )
        return Data(key.withUnsafeBytes { Array($0) })
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func describe(_ error: any Error) -> String {
        guard let authError = error as? ASAuthorizationError else {
            return "Failed: \(error.localizedDescription)"
        }
        switch authError.code {
        case .canceled: return "Cancelled."
        case .notInteractive: return "Not interactive."
        case .invalidResponse: return "Invalid response. Usually the domain is not associated."
        case .notHandled: return "Not handled. Check webcredentials entitlement and AASA."
        case .failed: return "Failed. Often no passcode set, or AASA not reachable."
        default: return "ASAuthorizationError \(authError.code.rawValue): \(authError.localizedDescription)"
        }
    }

    private func add(_ symbol: String, _ message: String) {
        log.append(Line(symbol: symbol == "ok" ? "✓" : "✗", message: message))
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return Data(bytes)
    }
}

extension PRFProbe: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
#endif
