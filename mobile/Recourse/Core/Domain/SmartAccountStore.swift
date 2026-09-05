import Foundation
import Observation

/// The account's Safe, from the phone's side: whether it exists, whether this phone
/// is its Device Key, and the one-time moves that get it there.
///
/// The record is cached per signed-in account so the Safe is the wallet from the
/// first frame after launch, then checked against the server, whose answer wins.
@MainActor
@Observable
final class SmartAccountStore {
    enum Phase: Equatable {
        /// Nothing known yet.
        case unknown
        /// Signed in, no Safe. The next step is to provision one.
        case none
        /// The Safe is being created. The text is what the screen shows.
        case provisioning(String)
        /// The Safe is live and this phone holds its Device Key.
        case live
        /// The Safe is live and its Device Key is on another phone. The way in is the
        /// emailed code.
        case needsRestore
        case failed(String)
    }

    private(set) var record: SmartAccountRecord?
    private(set) var phase: Phase = .unknown
    /// The Safe signer while live; the gateway builds its submitter from it.
    private(set) var safeSigner: SafeAccountSigner?
    /// The provision in flight, so a second caller waits on it instead of asking the
    /// server to deploy twice.
    private var provisioning: Task<SmartAccountRecord, Error>?

    let deviceKey: any DeviceKeySigning
    private let configuration: AppConfiguration
    private let session: AccountSession
    private let signer: SwitchableSigner
    private let api: any SmartAccountAPI
    private let defaults: UserDefaults

    init(
        configuration: AppConfiguration,
        session: AccountSession,
        signer: SwitchableSigner,
        api: any SmartAccountAPI,
        deviceKey: any DeviceKeySigning = SecureEnclaveDeviceKey(),
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.session = session
        self.signer = signer
        self.api = api
        self.deviceKey = deviceKey
        self.defaults = defaults
    }

    var isLive: Bool { phase == .live }

    var safeAddress: EthereumAddress? {
        record.map { EthereumAddress(trusted: $0.safe) }
    }

    // MARK: Lifecycle

    /// Adopt the cached record immediately, then ask the server.
    func load() async {
        if let cached = cachedRecord(), cached.isLive {
            await adopt(cached)
        }
        await refresh()
    }

    /// The server's view, reconciled with the key this phone holds.
    func refresh() async {
        guard session.isAuthenticated else {
            phase = .unknown
            return
        }
        do {
            let remote = try await session.withAccessToken { try await api.current(accessToken: $0) }
            guard remote.isLive else {
                await finish()
                return
            }
            if try await holdsDeviceKey(for: remote) {
                await adopt(remote)
            } else {
                record = remote
                phase = .needsRestore
                deactivate()
            }
        } catch SmartAccountAPIError.none {
            record = nil
            phase = .none
            deactivate()
        } catch {
            // Offline keeps whatever was cached; a fresh install with no cache waits.
            if phase == .unknown, record == nil { phase = .unknown }
        }
    }

    /// The server has a row it never finished deploying. It finishes on the next
    /// provision call, so the phone makes that call instead of showing a spinner
    /// nothing will ever stop. A failure waits for the user's "Try again", which is
    /// the same call.
    private func finish() async {
        if case .failed = phase { return }
        guard provisioning == nil else { return }
        phase = .provisioning("Finishing your account")
        _ = try? await provision()
    }

    /// Create the Safe for the keys this phone holds. Safe to call again after a failure.
    func provision() async throws -> SmartAccountRecord {
        if let provisioning { return try await provisioning.value }
        let task = Task { try await createSafe() }
        provisioning = task
        defer { provisioning = nil }
        return try await task.value
    }

    private func createSafe() async throws -> SmartAccountRecord {
        phase = .provisioning("Preparing your keys")
        do {
            let publicKey = try await deviceKey.publicKey()
            let cloudOwner = try await signer.cloud.address()
            phase = .provisioning("Creating your account on Arc")
            let created = try await session.withAccessToken {
                try await api.provision(cloudOwner: cloudOwner.value, deviceKey: publicKey, accessToken: $0)
            }
            guard created.isLive else {
                throw SmartAccountAPIError.rejected(status: 500, message: "The account did not finish deploying. Try again.")
            }
            await adopt(created)
            return created
        } catch {
            phase = .failed(Self.describe(error))
            throw error
        }
    }

    /// Whether the key on this phone is the one the Safe names.
    private func holdsDeviceKey(for record: SmartAccountRecord) async throws -> Bool {
        guard await deviceKey.hasKey() else { return false }
        let mine = try await deviceKey.publicKey()
        return mine.xHex.lowercased() == record.deviceX.lowercased()
            && mine.yHex.lowercased() == record.deviceY.lowercased()
    }

    private func adopt(_ record: SmartAccountRecord) async {
        self.record = record
        cache(record)
        let safe = SafeAccountSigner(
            account: record,
            cloud: signer.cloud,
            device: deviceKey,
            chainID: configuration.chainID
        )
        safeSigner = safe
        await signer.activate(safe)
        phase = .live
    }

    private func deactivate() {
        safeSigner = nil
        Task { await signer.activate(nil) }
    }

    // MARK: Moving an older wallet across

    /// Whether the Cloud Key still holds money the Safe should have.
    ///
    /// Only accounts that predate the Safe have any: their key was the wallet. The
    /// amount committed to uncashed cheques stays behind, because those cheques were
    /// signed by the key and cash against its balance.
    func cloudBalanceToSweep(reader: any ContractReading, committed: USDCAmount) async throws -> USDCAmount? {
        guard isLive else { return nil }
        let cloudOwner = try await signer.cloud.address()
        let balance = try await reader.usdcBalance(of: cloudOwner)
        // The key pays this transfer's gas from the same balance, so a sliver stays.
        let gasReserve = USDCAmount(baseUnits: 10_000)
        let movable = balance.baseUnits.subtractingReportingOverflow(committed.baseUnits + gasReserve.baseUnits)
        guard !movable.overflow, movable.partialValue >= USDCAmount.base / 100 else { return nil }
        return USDCAmount(baseUnits: movable.partialValue)
    }

    /// Send that balance to the Safe, signed by the key that holds it.
    func sweepCloudBalance(_ amount: USDCAmount, gateway: any ContractGateway) async throws -> ChainHash {
        guard let safeAddress else { throw SmartAccountAPIError.none }
        let hash = try await gateway.transferUSDC(to: safeAddress, amount: amount)
        _ = try await gateway.waitForReceipt(transactionHash: hash)
        return hash
    }

    // MARK: Restore on a new phone

    func requestRecoveryCode() async throws -> RecoveryCodeIssued {
        try await session.withAccessToken { try await api.requestRecoveryCode(accessToken: $0) }
    }

    func verifyRecoveryCode(_ code: String) async throws -> RecoveryGrant {
        try await session.withAccessToken { try await api.verifyRecoveryCode(code, accessToken: $0) }
    }

    /// Move the account's Device Key to this phone.
    ///
    /// The server stages the swap and hands back its hash; the Cloud Key signs it
    /// here; the server adds the Recovery Key and submits. The phone checks that the
    /// swap really names the key it just made before signing anything.
    func restoreDevice(grantID: String) async throws -> DeviceRotationOutcome {
        guard let record else { throw SmartAccountAPIError.none }
        let publicKey = try await deviceKey.publicKey()
        let plan = try await session.withAccessToken {
            try await api.prepareDeviceSwap(grantID: grantID, deviceKey: publicKey, accessToken: $0)
        }

        let safe = EthereumAddress(trusted: record.safe)
        let expected = SafeHashing.transactionHash(
            safe: safe,
            chainID: configuration.chainID,
            to: safe,
            data: SafeCalldata.swapOwner(
                previous: EthereumAddress(trusted: plan.prevOwner),
                old: EthereumAddress(trusted: plan.oldDeviceOwner),
                new: EthereumAddress(trusted: plan.newDeviceOwner)
            ),
            nonce: BigUIntFromHex(plan.safeNonce)
        )
        guard expected.hexString.lowercased() == plan.safeTxHash.lowercased() else {
            throw SmartAccountAPIError.rejected(status: 409, message: "The staged swap is not the one this phone asked for.")
        }

        let cloudSignature = try await signer.signHash(expected)
        let outcome = try await session.withAccessToken {
            try await api.executeDeviceSwap(rotationID: plan.rotationId, cloudSignature: cloudSignature, accessToken: $0)
        }
        await refresh()
        return outcome
    }

    // MARK: Cache

    private var cacheKey: String? {
        ActiveAccount.scope.map { "recourse.smartAccount.\($0)" }
    }

    private func cachedRecord() -> SmartAccountRecord? {
        guard let cacheKey, let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(SmartAccountRecord.self, from: data)
    }

    private func cache(_ record: SmartAccountRecord) {
        guard let cacheKey, let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    /// The reason, in words. A blanket "try again" hides which of the three keys or
    /// two servers refused, and that is exactly what someone locked out needs to know.
    static func describe(_ error: Error) -> String {
        if let error = error as? SmartAccountAPIError { return error.message }
        if let error = error as? DeviceKeyError {
            switch error {
            case .enclaveUnavailable(let reason): return "This phone could not make a device key: \(reason)"
            case .notFound: return "This phone has no device key yet. Close the app and open it again."
            case .signingFailed(let reason): return "This phone's key could not sign: \(reason)"
            case .malformedSignature, .digestNotThirtyTwoBytes: return "This phone's key produced a signature the account cannot read."
            }
        }
        if let error = error as? BuyerSignerError {
            switch error {
            case .missingPassword, .corruptKeystore, .invalidAccount:
                return "The Cloud Key on this phone cannot be read. Check that iCloud Keychain is on for this Apple ID, then try again."
            case .signingFailed: return "The Cloud Key could not sign."
            case .walletAlreadyExists: return "This phone already holds a different Cloud Key."
            case .entropyUnavailable, .keystoreCreationFailed, .keystoreSerializationFailed:
                return "This phone could not make a Cloud Key."
            }
        }
        if error is URLError { return "No connection to Recourse. Try again." }
        if error is DecodingError { return "Recourse answered in a shape this app did not expect." }
        return "Something went wrong: \(String(describing: error))"
    }
}

private func BigUIntFromHex(_ hex: String) -> BigUInt {
    BigUInt(hex.dropFirst(hex.hasPrefix("0x") ? 2 : 0), radix: 16) ?? 0
}

import BigInt
