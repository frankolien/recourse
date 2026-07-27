import Foundation

struct AppConfiguration: Sendable {
    let rpcURL: URL
    let chainID: UInt64
    let chainName: String
    let escrowAddress: EthereumAddress
    let policyRegistryAddress: EthereumAddress
    let settlementVaultAddress: EthereumAddress
    let usdcAddress: EthereumAddress
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

    // Same inbox the web support page publishes; the settings screen builds
    // mailto links from it.
    static let supportEmail = "gkenny896@gmail.com"

    // Google iOS OAuth client id: a public identifier (it ships in every Google-enabled
    // app bundle), overridable for a different Google project. The backend accepts this
    // audience via GOOGLE_IOS_CLIENT_ID.
    static let googleIOSClientID = ProcessInfo.processInfo.environment["RECOURSE_GOOGLE_IOS_CLIENT_ID"]
        ?? "181083896548-8f527b3qmqb9oc6iqqsduc53214lenqm.apps.googleusercontent.com"
}
