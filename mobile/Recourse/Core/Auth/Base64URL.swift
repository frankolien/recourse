import Foundation

extension Data {
    /// base64url, unpadded, as WebAuthn and OAuth PKCE both require.
    ///
    /// Shared because standard base64 is accepted by neither, and the failure is quiet:
    /// the value encodes fine, travels fine, and is rejected at the far end.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The inverse, restoring the padding base64url drops.
    init?(base64URLEncoded string: String) {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 {
            padded += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: padded)
    }
}
