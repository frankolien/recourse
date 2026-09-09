import AuthenticationServices
import XCTest
@testable import Recourse

/// The store against a server that left the account half made: a row in
/// `deploying` that only another provision call can finish.
@MainActor
final class SmartAccountStoreTests: XCTestCase {
    func testADeployingRecordIsFinishedByThePhoneThatSeesIt() async throws {
        let api = SmartAccountAPIFake(current: record(status: "deploying"), provisioned: .success(record(status: "live")))
        let store = try await makeStore(api: api)

        await store.refresh()

        XCTAssertEqual(store.phase, .live)
        XCTAssertEqual(store.record?.status, "live")
        let calls = await api.provisionCalls
        XCTAssertEqual(calls, 1)
    }

    func testAFinishThatFailsWaitsForTheUserInsteadOfLooping() async throws {
        let refusal = "this account already has a device key; restore this phone through recovery"
        let api = SmartAccountAPIFake(
            current: record(status: "deploying"),
            provisioned: .failure(SmartAccountAPIError.rejected(status: 409, message: refusal))
        )
        let store = try await makeStore(api: api)

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.phase, .failed(refusal))
        let calls = await api.provisionCalls
        XCTAssertEqual(calls, 1)
    }

    func testTwoCallersShareOneProvision() async throws {
        let api = SmartAccountAPIFake(current: record(status: "deploying"), provisioned: .success(record(status: "live")))
        let store = try await makeStore(api: api)

        async let first = store.provision()
        async let second = store.provision()
        _ = try await (first, second)

        XCTAssertEqual(store.phase, .live)
        let calls = await api.provisionCalls
        XCTAssertEqual(calls, 1)
    }

    func testALiveWalletElsewhereAndNoKeyHereIsARestoreAndMintsNothing() async throws {
        let api = SmartAccountAPIFake(current: record(status: "live"), provisioned: .success(record(status: "live")))
        let cloud = AbsentCloudSigner()
        let store = try await makeStore(api: api, cloud: cloud)

        await store.load()

        XCTAssertEqual(store.phase, .needsRestore)
        let minting = await cloud.mintsOnDemand
        XCTAssertFalse(minting, "no key may appear while the account's wallet is elsewhere")
        let calls = await api.provisionCalls
        XCTAssertEqual(calls, 0)
    }

    func testAnAccountWithNoWalletMayMintOne() async throws {
        let api = SmartAccountAPIFake(current: nil, provisioned: .success(record(status: "live")))
        let cloud = AbsentCloudSigner()
        let store = try await makeStore(api: api, cloud: cloud)

        await store.load()

        XCTAssertEqual(store.phase, .none)
        let minting = await cloud.mintsOnDemand
        XCTAssertTrue(minting)
    }

    // MARK: Fixtures

    func testStoppingARecoveryRemovesItFromWhatIsShown() async throws {
        let api = SmartAccountAPIFake(current: nil, provisioned: .failure(SmartAccountAPIError.invalidResponse))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        await api.setPending([
            PendingRecovery(
                rotationId: 7,
                kind: "cloud",
                readyAt: formatter.string(from: Date().addingTimeInterval(3600)),
                createdAt: formatter.string(from: Date())
            )
        ])
        let store = try await makeStore(api: api)

        await store.refreshPendingRecoveries()
        let shown = await store.pendingRecoveries
        XCTAssertEqual(shown.count, 1, "the warning is on screen")

        try await store.stopRecovery(shown[0])
        let after = await store.pendingRecoveries
        XCTAssertTrue(after.isEmpty, "and gone once stopped")
        let cancelled = await api.cancelled
        XCTAssertEqual(cancelled, ["cloud-7"], "the right one was stopped")
    }

    private func makeStore(api: SmartAccountAPIFake, cloud: any BuyerSigner = FixedCloudSigner()) async throws -> SmartAccountStore {
        let account = AuthenticatedAccount(
            accountID: 11,
            providerUserID: "apple-user-123",
            email: "frank@example.com",
            givenName: "Frank",
            familyName: "Olien"
        )
        let grant = AccountSessionGrant(
            accessToken: "access",
            refreshToken: "refresh",
            accessExpiresAt: 4_000_000_000,
            refreshExpiresAt: 4_100_000_000,
            account: account
        )
        let sessionStore = AccountSessionStore(secureStore: AccountSessionMemoryStore())
        try await sessionStore.save(grant)
        let session = AccountSession(
            store: sessionStore,
            credentialChecker: FixedAppleCredentialChecker(state: .authorized),
            api: AccountAPIMock(profile: account, refreshedGrant: grant)
        )
        await session.restore()
        XCTAssertTrue(session.isAuthenticated)

        return SmartAccountStore(
            configuration: .live,
            session: session,
            signer: SwitchableSigner(cloud: cloud),
            api: api,
            deviceKey: FixedDeviceKey(),
            defaults: UserDefaults(suiteName: "SmartAccountStoreTests-\(UUID().uuidString)")!
        )
    }

    private func record(status: String) -> SmartAccountRecord {
        SmartAccountRecord(
            safe: "0x93B5497A85be58436E6667140C9AaC7Fac9E5304",
            cloudOwner: "0x1111111111111111111111111111111111111111",
            deviceOwner: "0x2222222222222222222222222222222222222222",
            deviceX: "0x" + String(repeating: "11", count: 32),
            deviceY: "0x" + String(repeating: "22", count: 32),
            recoveryOwner: "0x3333333333333333333333333333333333333333",
            threshold: 2,
            status: status,
            entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032",
            module: "0x4444444444444444444444444444444444444444"
        )
    }
}

private actor SmartAccountAPIFake: SmartAccountAPI {
    let current: SmartAccountRecord?
    let provisioned: Result<SmartAccountRecord, Error>
    private(set) var provisionCalls = 0

    init(current: SmartAccountRecord?, provisioned: Result<SmartAccountRecord, Error>) {
        self.current = current
        self.provisioned = provisioned
    }

    func current(accessToken: String) async throws -> SmartAccountRecord {
        guard let current else { throw SmartAccountAPIError.none }
        return current
    }

    func provision(cloudOwner: String, deviceKey: DevicePublicKey, accessToken: String) async throws -> SmartAccountRecord {
        provisionCalls += 1
        // Long enough that a second caller arrives while the first is still waiting.
        try await Task.sleep(for: .milliseconds(80))
        return try provisioned.get()
    }

    func requestRecoveryCode(accessToken: String) async throws -> RecoveryCodeIssued {
        throw SmartAccountAPIError.invalidResponse
    }

    func verifyRecoveryCode(_ code: String, accessToken: String) async throws -> RecoveryGrant {
        throw SmartAccountAPIError.invalidResponse
    }

    func prepareDeviceSwap(grantID: String, deviceKey: DevicePublicKey, accessToken: String) async throws -> DeviceRotationPlan {
        throw SmartAccountAPIError.invalidResponse
    }

    func executeDeviceSwap(rotationID: Int64, cloudSignature: Data, accessToken: String) async throws -> DeviceRotationOutcome {
        throw SmartAccountAPIError.invalidResponse
    }

    var pending: [PendingRecovery] = []
    private(set) var cancelled: [String] = []

    func setPending(_ list: [PendingRecovery]) {
        pending = list
    }

    func pendingRecoveries(accessToken: String) async throws -> [PendingRecovery] {
        pending
    }

    func cancelRecovery(kind: String, rotationID: Int64, accessToken: String) async throws {
        cancelled.append("\(kind)-\(rotationID)")
        pending.removeAll { $0.kind == kind && $0.rotationId == rotationID }
    }

    func abandon(grantID: String, accessToken: String) async throws {}
}

private struct FixedDeviceKey: DeviceKeySigning {
    func publicKey() async throws -> DevicePublicKey {
        DevicePublicKey(x: Data(repeating: 0x11, count: 32), y: Data(repeating: 0x22, count: 32))
    }

    func sign(digest: Data) async throws -> Data {
        throw DeviceKeyError.signingFailed("fixture")
    }

    func hasKey() async -> Bool { true }

    func reset() async throws {}
}

private actor FixedCloudSigner: BuyerSigner {
    func address() async throws -> EthereumAddress {
        EthereumAddress(trusted: "0x1111111111111111111111111111111111111111")
    }

    func sign(_ transaction: UnsignedTransaction) async throws -> Data {
        throw BuyerSignerError.signingFailed
    }

    func signEIP712(_ typedData: Data) async throws -> Data {
        throw BuyerSignerError.signingFailed
    }

    func reset() async throws {}
}

/// A phone with no Cloud Key at all, which remembers whether it was allowed to make one.
private actor AbsentCloudSigner: BuyerSigner {
    private(set) var mintsOnDemand = true

    func address() async throws -> EthereumAddress {
        guard mintsOnDemand else { throw BuyerSignerError.walletElsewhere }
        return EthereumAddress(trusted: "0x9999999999999999999999999999999999999999")
    }

    func sign(_ transaction: UnsignedTransaction) async throws -> Data {
        throw BuyerSignerError.signingFailed
    }

    func signEIP712(_ typedData: Data) async throws -> Data {
        throw BuyerSignerError.signingFailed
    }

    func reset() async throws {}

    func hasWallet() async -> Bool { false }

    func setMintsOnDemand(_ allowed: Bool) async {
        mintsOnDemand = allowed
    }
}

/// The warning a person sees when someone is taking their account, and the button
/// that ends it. Both are the reason the server's delay is worth anything.
final class PendingRecoveryTests: XCTestCase {
    private func recovery(kind: String, readyIn seconds: TimeInterval) -> PendingRecovery {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return PendingRecovery(
            rotationId: 7,
            kind: kind,
            readyAt: formatter.string(from: Date().addingTimeInterval(seconds)),
            createdAt: formatter.string(from: Date())
        )
    }

    func testTheServerTimeIsReadEvenWithFractionalSeconds() {
        let pending = recovery(kind: "cloud", readyIn: 3600)
        XCTAssertNotNil(pending.ready, "a time the server actually sends must parse")
    }

    func testTimesWithoutFractionalSecondsStillRead() {
        let pending = PendingRecovery(rotationId: 1, kind: "device", readyAt: "2026-09-09T12:00:00Z", createdAt: "2026-09-09T11:00:00Z")
        XCTAssertNotNil(pending.ready)
    }

    func testEachKeyIsNamedInWordsRatherThanJargon() {
        XCTAssertEqual(recovery(kind: "cloud", readyIn: 60).whatIsChanging, "Your iCloud key")
        XCTAssertEqual(recovery(kind: "device", readyIn: 60).whatIsChanging, "Your phone key")
    }

}
