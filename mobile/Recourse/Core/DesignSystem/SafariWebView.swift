import SafariServices
import SwiftUI

/// In-app browser sheet for web pages like the privacy policy and terms.
/// SFSafariViewController instead of an open-in-Safari bounce: the user stays
/// in the app, gets Reader and a Done button, and Safari's cookies and
/// autofill still work because the controller runs out of process.
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(RecourseColor.ledger)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Identifiable wrapper so a URL can drive `.sheet(item:)`.
struct WebPageLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
