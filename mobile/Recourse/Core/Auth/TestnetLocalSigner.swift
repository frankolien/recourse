import Foundation
import Security
@preconcurrency import BigInt
@preconcurrency import Web3Core
@preconcurrency import web3swift

actor TestnetLocalSigner: BuyerSigner {
    enum AccountKey {
        static let keystore = "testnet-keystore-v3"
        static let password = "testnet-keystore-password"
    }

    private let store: any SecureDataStore
    private let authorizer: any TransactionAuthorizing
    private let scope: @Sendable () -> String?

    init(
        store: any SecureDataStore = KeychainStore(synchronizable: true),
        authorizer: any TransactionAuthorizing = DeviceOwnerTransactionAuthorizer(),
        scope: @escaping @Sendable () -> String? = { ActiveAccount.scope }
    ) {
        self.store = store
        self.authorizer = authorizer
        self.scope = scope
    }

    // One keystore per signed-in account. These used to be fixed names, so every
    // account that signed in on a device unlocked the same wallet and therefore
    // reported the same balance.
    private var keystoreAccount: String {
        scope().map { "\(AccountKey.keystore).\($0)" } ?? AccountKey.keystore
    }

    private var passwordAccount: String {
        scope().map { "\(AccountKey.password).\($0)" } ?? AccountKey.password
    }

    func address() async throws -> EthereumAddress {
        let keystore = try await loadOrCreateKeystore()
        guard let account = keystore.addresses?.first else {
            throw BuyerSignerError.invalidAccount
        }
        return try EthereumAddress(account.address)
    }

    func sign(_ transaction: UnsignedTransaction) async throws -> Data {
        try await authorizer.authorizeTransaction()
        let (keystore, password) = try await loadCredentials()
        guard let account = keystore.addresses?.first,
              account.address.lowercased() == transaction.from.value.lowercased(),
              let destination = Web3Core.EthereumAddress(transaction.to.value) else {
            throw BuyerSignerError.invalidAccount
        }

        var web3Transaction = CodableTransaction(
            type: .legacy,
            to: destination,
            nonce: BigUInt(transaction.nonce),
            chainID: BigUInt(transaction.chainID),
            value: 0,
            data: transaction.data,
            gasLimit: BigUInt(transaction.gasLimit),
            gasPrice: BigUInt(transaction.gasPrice)
        )
        web3Transaction.from = account

        do {
            try Web3Signer.signTX(
                transaction: &web3Transaction,
                keystore: keystore,
                account: account,
                password: password
            )
        } catch {
            throw BuyerSignerError.signingFailed
        }
        guard let encoded = web3Transaction.encode(for: .transaction) else {
            throw BuyerSignerError.signingFailed
        }
        return encoded
    }

    func signEIP712(_ typedData: Data) async throws -> Data {
        try await authorizer.authorizeTransaction()
        let (keystore, password) = try await loadCredentials()
        guard let account = keystore.addresses?.first else {
            throw BuyerSignerError.invalidAccount
        }

        do {
            let payload = try EIP712Parser.parse(typedData)
            return try Web3Signer.signEIP712(
                payload,
                keystore: keystore,
                account: account,
                password: password
            )
        } catch {
            throw BuyerSignerError.signingFailed
        }
    }

    func signHash(_ digest: Data) async throws -> Data {
        guard digest.count == 32 else { throw BuyerSignerError.signingFailed }
        let (keystore, password) = try await loadCredentials()
        guard let account = keystore.addresses?.first else {
            throw BuyerSignerError.invalidAccount
        }
        let privateKey: Data
        do {
            privateKey = try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
        } catch {
            throw BuyerSignerError.signingFailed
        }
        defer { _ = privateKey }
        let (serialized, _) = SECP256K1.signForRecovery(hash: digest, privateKey: privateKey)
        guard var signature = serialized, signature.count == 65 else {
            throw BuyerSignerError.signingFailed
        }
        // secp256k1 hands back the recovery id as 0 or 1; the Safe reads 27 or 28.
        let last = signature.index(before: signature.endIndex)
        if signature[last] < 27 { signature[last] += 27 }
        return signature
    }

    /// The escape hatch. Hands back the raw signing key so a wallet created here can
    /// be moved somewhere else, or recovered if this app goes away.
    ///
    /// Deliberately not a BIP39 phrase. These keystores hold random keys rather than
    /// keys derived from a seed, so encoding one as 24 words would produce something
    /// that looks like a standard recovery phrase but resolves to a different address
    /// in any other wallet: the importer treats a mnemonic as a seed and walks
    /// m/44'/60'/0'/0/0 from it. Someone importing that phrase would see an empty
    /// account and reasonably conclude their funds were gone. A private key imports
    /// as exactly the account it came from.
    ///
    /// Gated behind the same authorizer as signing, because possession of this is
    /// possession of the funds.
    func exportPrivateKey() async throws -> Data {
        try await authorizer.authorizeTransaction()
        let (keystore, password) = try await loadCredentials()
        guard let account = keystore.addresses?.first else {
            throw BuyerSignerError.invalidAccount
        }
        do {
            return try keystore.UNSAFE_getPrivateKeyData(password: password, account: account)
        } catch {
            throw BuyerSignerError.signingFailed
        }
    }

    /// Whether this account already has a keystore on this device, checked without
    /// creating one. Same question importPrivateKey asks before refusing, so the two
    /// can never disagree about whether there is something here to lose.
    func hasWallet() async -> Bool {
        ((try? await store.load(account: keystoreAccount)) ?? nil) != nil
    }

    /// Install a recovered private key as this account's wallet.
    ///
    /// The counterpart of exportPrivateKey, and the last step of restoring a backup on
    /// a new device. It refuses to run when a keystore already exists rather than
    /// overwriting one: on a phone that has been used, the existing key may hold funds
    /// nobody has a copy of, and silently replacing it would destroy them. Callers that
    /// genuinely mean to replace a wallet call reset() first and say so on screen.
    func importPrivateKey(_ privateKey: Data) async throws {
        if try await store.load(account: keystoreAccount) != nil {
            throw BuyerSignerError.walletAlreadyExists
        }
        let password = try makePassword()
        guard let keystore = try EthereumKeystoreV3(privateKey: privateKey, password: password) else {
            throw BuyerSignerError.keystoreCreationFailed
        }
        guard let serialized = try keystore.serialize() else {
            throw BuyerSignerError.keystoreSerializationFailed
        }
        try await store.save(serialized, account: keystoreAccount)
        try await store.save(Data(password.utf8), account: passwordAccount)
    }

    func reset() async throws {
        try await store.delete(account: keystoreAccount)
        try await store.delete(account: passwordAccount)
    }

    private var mintsOnDemand = true

    func setMintsOnDemand(_ allowed: Bool) async {
        mintsOnDemand = allowed
    }

    private func loadOrCreateKeystore() async throws -> EthereumKeystoreV3 {
        if let data = try await store.load(account: keystoreAccount) {
            guard let keystore = EthereumKeystoreV3(data) else {
                throw BuyerSignerError.corruptKeystore
            }
            return keystore
        }

        if let adopted = try await adoptDeviceWideKeystore() {
            return adopted
        }

        guard mintsOnDemand else { throw BuyerSignerError.walletElsewhere }

        let password = try makePassword()
        guard let keystore = try EthereumKeystoreV3(password: password) else {
            throw BuyerSignerError.keystoreCreationFailed
        }
        guard let serialized = try keystore.serialize() else {
            throw BuyerSignerError.keystoreSerializationFailed
        }
        try await store.save(serialized, account: keystoreAccount)
        try await store.save(Data(password.utf8), account: passwordAccount)
        return keystore
    }

    /// Hands the pre-existing device-wide wallet to the first account that asks
    /// for one, then removes it so no second account can claim it too. Installs
    /// carrying a funded testnet wallet keep it instead of waking up empty.
    private func adoptDeviceWideKeystore() async throws -> EthereumKeystoreV3? {
        guard scope() != nil,
              let data = try await store.load(account: AccountKey.keystore),
              let password = try await store.load(account: AccountKey.password),
              let keystore = EthereumKeystoreV3(data) else {
            return nil
        }

        try await store.save(data, account: keystoreAccount)
        try await store.save(password, account: passwordAccount)
        try await store.delete(account: AccountKey.keystore)
        try await store.delete(account: AccountKey.password)
        return keystore
    }

    private func loadCredentials() async throws -> (EthereumKeystoreV3, String) {
        let keystore = try await loadOrCreateKeystore()
        guard let passwordData = try await store.load(account: passwordAccount),
              let password = String(data: passwordData, encoding: .utf8) else {
            throw BuyerSignerError.missingPassword
        }
        return (keystore, password)
    }

    private func makePassword() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw BuyerSignerError.entropyUnavailable
        }
        return Data(bytes).base64EncodedString()
    }
}
