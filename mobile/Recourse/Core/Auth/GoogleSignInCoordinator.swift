import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

// Native Google sign-in without the GoogleSignIn SDK: a standard OAuth 2.0
// authorization-code flow with PKCE through ASWebAuthenticationSession. iOS OAuth
// clients are public clients (no secret); PKCE binds the code to this app instance,
// and the backend independently verifies the returned ID token's signature and
// audience against GOOGLE_IOS_CLIENT_ID, so the app never has to trust this dance.
@MainActor
final class GoogleSignInCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum GoogleSignInError: Error {
        case cancelled
        case invalidCallback
        case tokenExchangeFailed
    }

    private let clientID: String
    private var activeSession: ASWebAuthenticationSession?

    init(clientID: String) {
        self.clientID = clientID
    }

    // Google's iOS redirect scheme is the reversed client id.
    private var callbackScheme: String {
        let prefix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    // Runs the full browser round trip and returns a Google ID token ready for the
    // backend exchange.
    func signIn() async throws -> String {
        let verifier = Self.randomURLSafe(byteCount: 48)
        let challenge = Self.s256(verifier)
        let state = Self.randomURLSafe(byteCount: 16)
        let redirectURI = "\(callbackScheme):/oauth2redirect"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components.url else {
            throw GoogleSignInError.invalidCallback
        }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let sessionError = error as? ASWebAuthenticationSessionError,
                          sessionError.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GoogleSignInError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.start()
            activeSession = session
        }
        activeSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        // The state echo defeats a forged callback: only our own round trip knows it.
        guard items?.first(where: { $0.name == "state" })?.value == state,
              let code = items?.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.invalidCallback
        }
        return try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: String
    ) async throws -> String {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleSignInError.tokenExchangeFailed
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        request.httpBody = form
            .map { "\($0.key)=\(Self.formEncoded($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              let payload = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw GoogleSignInError.tokenExchangeFailed
        }
        return payload.idToken
    }

    private struct TokenResponse: Decodable {
        let idToken: String

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    private static func formEncoded(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        ) ?? value
    }
}
