import AuthenticationServices
import Foundation
import UIKit

/// Runs the two WebAuthn ceremonies against the platform authenticator.
///
/// The server speaks webauthn-rs, which expects the browser's JSON shapes; iOS hands
/// back raw `Data`. Everything here is that translation, and the translation is
/// base64url without padding, which is the one detail that silently breaks a ceremony:
/// standard base64 verifies fine locally and is rejected by the server.
///
/// Requires the relying party to be listed in the app's `webcredentials` entitlement
/// and served in that domain's apple-app-site-association. Without both, the system
/// refuses before the user sees a prompt.
final class PasskeyCoordinator: NSObject, Sendable {
    enum Failure: Error, Equatable {
        case cancelled
        case unsupported
        case failed
    }

    private let relyingParty: String

    init(relyingParty: String) {
        self.relyingParty = relyingParty
    }

    /// Create a passkey on this device for an account.
    func register(
        challenge: Data,
        userID: Data,
        displayName: String
    ) async throws -> RegistrationCredential {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingParty
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: displayName,
            userID: userID
        )
        guard case .registration(let credential) = try await perform([request]) else {
            throw Failure.failed
        }
        return credential
    }

    /// Prove possession of a passkey already registered for the account.
    func assert(challenge: Data, allowedCredentialIDs: [Data]) async throws -> AssertionCredential {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingParty
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if !allowedCredentialIDs.isEmpty {
            request.allowedCredentials = allowedCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        guard case .assertion(let credential) = try await perform([request]) else {
            throw Failure.failed
        }
        return credential
    }

    private func perform(
        _ requests: [ASAuthorizationRequest]
    ) async throws -> PasskeyOutcome {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let delegate = PasskeyRequestDelegate()
                let controller = ASAuthorizationController(authorizationRequests: requests)
                controller.delegate = delegate
                controller.presentationContextProvider = delegate
                // The delegate is the controller's only strong reference holder here,
                // and a released delegate means a callback that never arrives.
                delegate.retain(controller: controller, continuation: continuation)
                controller.performRequests()
            }
        }
    }
}

/// The result of a ceremony, already reduced to values that can cross actors.
///
/// The reduction happens on the main actor inside the delegate rather than here,
/// because `ASAuthorizationCredential` is not Sendable and passing one out of the
/// callback is a data race the compiler is right to refuse.
enum PasskeyOutcome: Sendable {
    case registration(RegistrationCredential)
    case assertion(AssertionCredential)
}

/// What the server needs to finish registration, in its own encoding.
struct RegistrationCredential: Sendable {
    let id: String
    let clientDataJSON: String
    let attestationObject: String
}

/// What the server needs to finish authentication.
struct AssertionCredential: Sendable {
    let id: String
    let clientDataJSON: String
    let authenticatorData: String
    let signature: String
    let userHandle: String?
}

@MainActor
private final class PasskeyRequestDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<PasskeyOutcome, Error>?
    private var controller: ASAuthorizationController?
    private var selfReference: PasskeyRequestDelegate?

    func retain(
        controller: ASAuthorizationController,
        continuation: CheckedContinuation<PasskeyOutcome, Error>
    ) {
        self.controller = controller
        self.continuation = continuation
        selfReference = self
    }

    private func finish(_ result: Result<PasskeyOutcome, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        controller = nil
        selfReference = nil
        continuation.resume(with: result)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        switch authorization.credential {
        case let registration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            guard let attestation = registration.rawAttestationObject else {
                finish(.failure(PasskeyCoordinator.Failure.failed))
                return
            }
            finish(.success(.registration(RegistrationCredential(
                id: registration.credentialID.base64URLEncoded,
                clientDataJSON: registration.rawClientDataJSON.base64URLEncoded,
                attestationObject: attestation.base64URLEncoded
            ))))
        case let assertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            finish(.success(.assertion(AssertionCredential(
                id: assertion.credentialID.base64URLEncoded,
                clientDataJSON: assertion.rawClientDataJSON.base64URLEncoded,
                authenticatorData: assertion.rawAuthenticatorData.base64URLEncoded,
                signature: assertion.signature.base64URLEncoded,
                userHandle: assertion.userID?.base64URLEncoded
            ))))
        default:
            finish(.failure(PasskeyCoordinator.Failure.failed))
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        switch (error as? ASAuthorizationError)?.code {
        case .canceled:
            finish(.failure(PasskeyCoordinator.Failure.cancelled))
        case .notHandled, .notInteractive:
            // Almost always the entitlement or the apple-app-site-association file,
            // which the user can do nothing about, so it gets its own case.
            finish(.failure(PasskeyCoordinator.Failure.unsupported))
        default:
            finish(.failure(PasskeyCoordinator.Failure.failed))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
