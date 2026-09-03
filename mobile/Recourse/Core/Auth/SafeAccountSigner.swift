import Foundation
@preconcurrency import web3swift

/// The account, as a signer: the Safe's address, and signatures from both active
/// keys packed the way the Safe reads them.
///
/// Everything that used to ask the on-device key for "my address" now gets the Safe,
/// so cheques are written from it, invoices name it, history is read for it and
/// deposits land in it. The two keys stay where they are: the Cloud Key is the same
/// keystore as before, the Device Key is the enclave. This type only combines them.
actor SafeAccountSigner: BuyerSigner {
    let account: SmartAccountRecord
    private let cloud: any BuyerSigner
    private let device: any DeviceKeySigning
    private let chainID: UInt64

    init(account: SmartAccountRecord, cloud: any BuyerSigner, device: any DeviceKeySigning, chainID: UInt64) {
        self.account = account
        self.cloud = cloud
        self.device = device
        self.chainID = chainID
    }

    var safe: EthereumAddress {
        EthereumAddress(trusted: account.safe)
    }

    func address() async throws -> EthereumAddress {
        safe
    }

    /// A Safe never signs a raw transaction; it executes operations. Anything that
    /// reaches for this is on the wrong path.
    func sign(_ transaction: UnsignedTransaction) async throws -> Data {
        throw BuyerSignerError.invalidAccount
    }

    /// Sign typed data as the Safe: the digest is wrapped in a Safe message and both
    /// keys sign that. The result is the packed owner signatures, which is what USDC
    /// hands back to the Safe's `isValidSignature` when the cheque is cashed.
    func signEIP712(_ typedData: Data) async throws -> Data {
        let digest: Data
        do {
            digest = try EIP712Parser.parse(typedData).signHash()
        } catch {
            throw BuyerSignerError.signingFailed
        }
        let messageHash = SafeHashing.messageHash(safe: safe, chainID: chainID, digest: digest)
        return try await signSafeHash(messageHash)
    }

    /// Both active keys over a hash the Safe framed, packed in owner order.
    func signSafeHash(_ hash: Data) async throws -> Data {
        let cloudSignature = try await cloud.signHash(hash)
        let deviceSignature = try await device.sign(digest: hash)
        return try SafeSignatures.pack([
            .ecdsa(owner: EthereumAddress(trusted: account.cloudOwner), signature: cloudSignature),
            .contract(owner: EthereumAddress(trusted: account.deviceOwner), signature: deviceSignature),
        ])
    }

    /// The Cloud Key alone, for the one signature the Safe takes from it without the
    /// Device Key: approving the swap that replaces a lost Device Key.
    func signWithCloudKey(_ hash: Data) async throws -> Data {
        try await cloud.signHash(hash)
    }

    /// A signature with the right shape and no meaning, for gas estimation.
    func placeholderSignature() throws -> Data {
        try SafeSignatures.pack([
            .ecdsa(owner: EthereumAddress(trusted: account.cloudOwner), signature: Data(repeating: 0xff, count: 64) + Data([27])),
            .contract(owner: EthereumAddress(trusted: account.deviceOwner), signature: Data(repeating: 0xff, count: 64)),
        ])
    }

    func hasWallet() async -> Bool {
        await cloud.hasWallet()
    }

    /// Exporting the Cloud Key is still the escape hatch: with it and the Recovery Key
    /// the account can be recovered outside Recourse through Safe's own tools.
    func exportPrivateKey() async throws -> Data {
        try await cloud.exportPrivateKey()
    }

    func importPrivateKey(_ privateKey: Data) async throws {
        try await cloud.importPrivateKey(privateKey)
    }

    func reset() async throws {
        try await cloud.reset()
    }
}
