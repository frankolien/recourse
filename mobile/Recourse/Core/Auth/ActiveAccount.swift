import Foundation

/// Which account this device is currently signed into.
///
/// Kept outside the session grant, and readable without awaiting anything, so
/// per-account storage can be scoped at the moment it is touched rather than
/// after session restore finishes. The signer is asked for an address early in
/// the launch sequence; if scoping depended on restore having completed first,
/// a refresh that landed in between would read another account's wallet.
///
/// The value is an identifier, not a secret, so it lives in defaults rather than
/// the keychain. What it scopes (keystores, order manifests) stays where it was.
enum ActiveAccount {
    private static let key = "recourse.activeAccountScope"

    /// Nil before anyone signs in, and after sign-out.
    static var scope: String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func set(_ account: AuthenticatedAccount?) {
        guard let account else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set("account-\(account.accountID)", forKey: key)
    }
}
