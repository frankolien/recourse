import Foundation

/// The app's one signer, whose identity changes once during a session: it is the
/// plain key until the account's Safe exists, and the Safe from then on.
///
/// Everything that holds a signer holds this one, so a store built at launch sees the
/// Safe the moment provisioning finishes, without being rebuilt. The Cloud Key stays
/// reachable throughout for the things only it can do: restore a backup, export, and
/// approve a device swap.
actor SwitchableSigner: BuyerSigner {
    let cloud: any BuyerSigner
    private var safe: SafeAccountSigner?

    init(cloud: any BuyerSigner) {
        self.cloud = cloud
    }

    /// The Safe signer once the account is live, or nil before.
    var safeSigner: SafeAccountSigner? { safe }

    func activate(_ signer: SafeAccountSigner?) {
        safe = signer
    }

    private var current: any BuyerSigner {
        safe ?? cloud
    }

    func address() async throws -> EthereumAddress {
        try await current.address()
    }

    func sign(_ transaction: UnsignedTransaction) async throws -> Data {
        try await current.sign(transaction)
    }

    func signEIP712(_ typedData: Data) async throws -> Data {
        try await current.signEIP712(typedData)
    }

    func signHash(_ digest: Data) async throws -> Data {
        try await cloud.signHash(digest)
    }

    func hasWallet() async -> Bool {
        await cloud.hasWallet()
    }

    func setMintsOnDemand(_ allowed: Bool) async {
        await cloud.setMintsOnDemand(allowed)
    }

    func exportPrivateKey() async throws -> Data {
        try await cloud.exportPrivateKey()
    }

    func importPrivateKey(_ privateKey: Data) async throws {
        try await cloud.importPrivateKey(privateKey)
    }

    func reset() async throws {
        try await cloud.reset()
        safe = nil
    }
}
