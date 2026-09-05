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

    // MARK: Fixtures

    private func makeStore(api: SmartAccountAPIFake) async throws -> SmartAccountStore {
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
            signer: SwitchableSigner(cloud: FixedCloudSigner()),
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
    let current: SmartAccountRecord
    let provisioned: Result<SmartAccountRecord, Error>
    private(set) var provisionCalls = 0

    init(current: SmartAccountRecord, provisioned: Result<SmartAccountRecord, Error>) {
        self.current = current
        self.provisioned = provisioned
    }

    func current(accessToken: String) async throws -> SmartAccountRecord {
        current
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
