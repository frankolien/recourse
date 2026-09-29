import Foundation

struct AppConfiguration: Sendable {
    let rpcURL: URL
    let chainID: UInt64
    let chainName: String
    let escrowAddress: EthereumAddress
    let policyRegistryAddress: EthereumAddress
    let settlementVaultAddress: EthereumAddress
    let usdcAddress: EthereumAddress
    // Both nil when no FX venue is deployed for this chain, which simply means the
    // app has no Convert rather than a broken one.
    let fxRouterAddress: EthereumAddress?
    let eurcAddress: EthereumAddress?
    let apiURL: URL
    let merchantWebURL: URL
    /// Where history is read from. Nil on a chain whose explorer an app cannot query.
    let explorerAPIURL: URL?
    /// Where a transaction link opens for a person.
    let explorerPageURL: URL

    init(
        rpcURL: URL,
        chainID: UInt64,
        chainName: String,
        escrowAddress: EthereumAddress,
        policyRegistryAddress: EthereumAddress,
        settlementVaultAddress: EthereumAddress,
        usdcAddress: EthereumAddress,
        fxRouterAddress: EthereumAddress? = nil,
        eurcAddress: EthereumAddress? = nil,
        apiURL: URL = AppConfiguration.apiURL(for: Deployment.current),
        merchantWebURL: URL = AppConfiguration.defaultMerchantWebURL,
        explorerAPIURL: URL? = Deployment.current.explorerAPIURL.flatMap(URL.init(string:)),
        explorerPageURL: URL = URL(string: Deployment.current.explorerPageURL)!
    ) {
        self.rpcURL = rpcURL
        self.chainID = chainID
        self.chainName = chainName
        self.escrowAddress = escrowAddress
        self.policyRegistryAddress = policyRegistryAddress
        self.settlementVaultAddress = settlementVaultAddress
        self.usdcAddress = usdcAddress
        self.fxRouterAddress = fxRouterAddress
        self.eurcAddress = eurcAddress
        self.apiURL = apiURL
        self.merchantWebURL = merchantWebURL
        self.explorerAPIURL = explorerAPIURL
        self.explorerPageURL = explorerPageURL
    }

    /// The chain this call is for.
    ///
    /// Computed rather than a constant, because Settings can point the app at another
    /// chain and every address, endpoint and service URL moves together when it does.
    /// Reading it is cheap: it is one UserDefaults lookup and a lookup in a table the
    /// build carries.
    static var live: AppConfiguration { of(Deployment.current) }

    static func of(_ book: ChainBook) -> AppConfiguration {
        AppConfiguration(
            rpcURL: URL(string: book.rpcURL)!,
            chainID: book.chainID,
            chainName: book.name,
            escrowAddress: EthereumAddress(trusted: book.escrow),
            policyRegistryAddress: EthereumAddress(trusted: book.policyRegistry),
            settlementVaultAddress: EthereumAddress(trusted: book.settlementVault),
            usdcAddress: EthereumAddress(trusted: book.usdc),
            fxRouterAddress: book.fxRouter.map { EthereumAddress(trusted: $0) },
            eurcAddress: book.eurc.map { EthereumAddress(trusted: $0) },
            apiURL: apiURL(for: book),
            merchantWebURL: defaultMerchantWebURL,
            explorerAPIURL: book.explorerAPIURL.flatMap(URL.init(string:)),
            explorerPageURL: URL(string: book.explorerPageURL)!
        )
    }

    // Each chain has its own service, because each has its own database and its own
    // sessions. Default to the deployed one rather than localhost: scheme env vars only
    // inject when Xcode launches the app, so a device install, a TestFlight build or a
    // Release build would otherwise fall back to 127.0.0.1, which is the phone itself,
    // and every call would fail. RECOURSE_API_URL still overrides for local work, and
    // overrides whichever chain is selected, which is what local work wants.
    private static func apiURL(for book: ChainBook) -> URL {
        if let override = ProcessInfo.processInfo.environment["RECOURSE_API_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: book.apiURL)!
    }

    private static let defaultMerchantWebURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_MERCHANT_URL"]
            ?? "https://recourse-arc.vercel.app/dashboard"
    )!

    // Public web origin the checkout QR links to. The Camera app opens it as a universal
    // link straight into this app when installed, and as a normal web page otherwise.
    // Must stay in sync with the applinks entitlement and the AASA the web app serves.
    static let webAppURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_WEB_URL"]
            ?? "https://recourse-arc.vercel.app"
    )!

    // The chain explorer. It is a Blockscout, and its API is how the app learns about
    // every USDC movement on the wallet, including the ones nothing in this app
    // initiated. The RPC could answer the same question through eth_getLogs, but the
    // public endpoint caps log queries at ten thousand entries and carries no
    // timestamps, so the explorer is the honest source for a history.
    /// The bundler that carries the account's operations. Pimlico's public endpoint
    /// names the chain in its path, so this is a fact about the chain rather than a
    /// constant: the testnet endpoint would accept a mainnet operation's bytes and
    /// submit them to the wrong chain. RECOURSE_BUNDLER_URL still overrides for local
    /// work, and overrides whichever chain is selected.
    var bundlerURL: URL {
        if let override = ProcessInfo.processInfo.environment["RECOURSE_BUNDLER_URL"], let url = URL(string: override) {
            return url
        }
        return URL(string: "https://public.pimlico.io/v2/\(chainID)/rpc")!
    }

    // Same inbox the web support page publishes; the settings screen builds
    // mailto links from it.
    static let supportEmail = "gkenny896@gmail.com"

    // Google iOS OAuth client id: a public identifier (it ships in every Google-enabled
    // app bundle), overridable for a different Google project. The backend accepts this
    // audience via GOOGLE_IOS_CLIENT_ID.
    static let googleIOSClientID = ProcessInfo.processInfo.environment["RECOURSE_GOOGLE_IOS_CLIENT_ID"]
        ?? "181083896548-8f527b3qmqb9oc6iqqsduc53214lenqm.apps.googleusercontent.com"

    // WebAuthn relying party. Must match the backend's WEBAUTHN_RP_ID and appear in the
    // app's webcredentials entitlement, or the system refuses the ceremony before the
    // user is ever prompted. Derived from the web origin so the three cannot drift.
    static let passkeyRelyingParty = webAppURL.host() ?? "recourse-arc.vercel.app"
}
