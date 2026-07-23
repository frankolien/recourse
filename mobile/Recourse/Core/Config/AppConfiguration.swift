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

    private static let defaultAPIURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_API_URL"]
            ?? "http://127.0.0.1:8080"
    )!

    private static let defaultMerchantWebURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_MERCHANT_URL"]
            ?? "http://127.0.0.1:3002/dashboard"
    )!
}
