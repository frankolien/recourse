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

    init(
        store: any SecureDataStore = KeychainStore(),
        authorizer: any TransactionAuthorizing = DeviceOwnerTransactionAuthorizer()
    ) {
        self.store = store
        self.authorizer = authorizer
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

    func reset() async throws {
        try await store.delete(account: AccountKey.keystore)
        try await store.delete(account: AccountKey.password)
    }

    private func loadOrCreateKeystore() async throws -> EthereumKeystoreV3 {
        if let data = try await store.load(account: AccountKey.keystore) {
            guard let keystore = EthereumKeystoreV3(data) else {
                throw BuyerSignerError.corruptKeystore
            }
            return keystore
        }

        let password = try makePassword()
        guard let keystore = try EthereumKeystoreV3(password: password) else {
            throw BuyerSignerError.keystoreCreationFailed
        }
        guard let serialized = try keystore.serialize() else {
            throw BuyerSignerError.keystoreSerializationFailed
        }
        try await store.save(serialized, account: AccountKey.keystore)
        try await store.save(Data(password.utf8), account: AccountKey.password)
        return keystore
    }

    private func loadCredentials() async throws -> (EthereumKeystoreV3, String) {
        let keystore = try await loadOrCreateKeystore()
        guard let passwordData = try await store.load(account: AccountKey.password),
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
