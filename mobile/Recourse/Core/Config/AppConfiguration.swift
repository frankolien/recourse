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
        apiURL: URL = AppConfiguration.defaultAPIURL,
        merchantWebURL: URL = AppConfiguration.defaultMerchantWebURL
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
    }

    static let live = AppConfiguration(
        rpcURL: URL(string: Deployment.rpcURL)!,
        chainID: Deployment.chainID,
        chainName: "Arc Testnet",
        escrowAddress: EthereumAddress(trusted: Deployment.escrow),
        policyRegistryAddress: EthereumAddress(trusted: Deployment.policyRegistry),
        settlementVaultAddress: EthereumAddress(trusted: Deployment.settlementVault),
        usdcAddress: EthereumAddress(trusted: Deployment.usdc),
        fxRouterAddress: Deployment.fxRouter.map { EthereumAddress(trusted: $0) },
        eurcAddress: Deployment.eurc.map { EthereumAddress(trusted: $0) },
        apiURL: defaultAPIURL,
        merchantWebURL: defaultMerchantWebURL
    )

    // Default to the live backend, not localhost: scheme env vars only inject when Xcode
    // launches the app, so a device install / TestFlight / Release build would otherwise
    // fall back to 127.0.0.1 (the phone itself) and every API call fails. RECOURSE_API_URL
    // still overrides for local development.
    private static let defaultAPIURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_API_URL"]
            ?? "https://api.frankolien.com"
    )!

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
    static let explorerURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_EXPLORER_URL"]
            ?? "https://testnet.arcscan.app"
    )!

    /// The bundler that carries the account's operations. Pimlico's public endpoint on
    /// testnet; a keyed endpoint on mainnet.
    static let bundlerURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_BUNDLER_URL"] ?? "https://public.pimlico.io/v2/5042002/rpc"
    )!

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
