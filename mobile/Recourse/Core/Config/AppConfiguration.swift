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

    init(
        rpcURL: URL,
        chainID: UInt64,
        chainName: String,
        escrowAddress: EthereumAddress,
        policyRegistryAddress: EthereumAddress,
        settlementVaultAddress: EthereumAddress,
        usdcAddress: EthereumAddress,
        apiURL: URL = AppConfiguration.defaultAPIURL
    ) {
        self.rpcURL = rpcURL
        self.chainID = chainID
        self.chainName = chainName
        self.escrowAddress = escrowAddress
        self.policyRegistryAddress = policyRegistryAddress
        self.settlementVaultAddress = settlementVaultAddress
        self.usdcAddress = usdcAddress
        self.apiURL = apiURL
    }

    static let live = AppConfiguration(
        rpcURL: URL(string: Deployment.rpcURL)!,
        chainID: Deployment.chainID,
        chainName: "Arc Testnet",
        escrowAddress: EthereumAddress(trusted: Deployment.escrow),
        policyRegistryAddress: EthereumAddress(trusted: Deployment.policyRegistry),
        settlementVaultAddress: EthereumAddress(trusted: Deployment.settlementVault),
        usdcAddress: EthereumAddress(trusted: Deployment.usdc),
        apiURL: defaultAPIURL
    )

    private static let defaultAPIURL = URL(
        string: ProcessInfo.processInfo.environment["RECOURSE_API_URL"]
            ?? "http://127.0.0.1:8080"
    )!
}
