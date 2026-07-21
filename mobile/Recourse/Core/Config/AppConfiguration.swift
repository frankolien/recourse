import Foundation

struct AppConfiguration: Sendable {
    let rpcURL: URL
    let chainID: UInt64
    let chainName: String
    let escrowAddress: EthereumAddress
    let policyRegistryAddress: EthereumAddress
    let settlementVaultAddress: EthereumAddress
    let usdcAddress: EthereumAddress

    static let live = AppConfiguration(
        rpcURL: URL(string: Deployment.rpcURL)!,
        chainID: Deployment.chainID,
        chainName: "Arc Testnet",
        escrowAddress: EthereumAddress(trusted: Deployment.escrow),
        policyRegistryAddress: EthereumAddress(trusted: Deployment.policyRegistry),
        settlementVaultAddress: EthereumAddress(trusted: Deployment.settlementVault),
        usdcAddress: EthereumAddress(trusted: Deployment.usdc)
    )
}
