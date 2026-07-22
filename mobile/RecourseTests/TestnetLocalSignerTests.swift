import XCTest
@testable import Recourse

final class TestnetLocalSignerTests: XCTestCase {
    func testCreatesAndReloadsTheSameKeychainAccount() async throws {
        let store = InMemorySecureDataStore()
        let firstSigner = TestnetLocalSigner(store: store, authorizer: AllowingTransactionAuthorizer())
        let firstAddress = try await firstSigner.address()
        let secondSigner = TestnetLocalSigner(store: store, authorizer: AllowingTransactionAuthorizer())
        let secondAddress = try await secondSigner.address()
        let accountCount = await store.accountCount()

        XCTAssertEqual(secondAddress, firstAddress)
        XCTAssertEqual(accountCount, 2)
    }

    func testSignsDeterministicLegacyTransaction() async throws {
        let authorizer = AllowingTransactionAuthorizer()
        let signer = TestnetLocalSigner(
            store: InMemorySecureDataStore(),
            authorizer: authorizer
        )
        let address = try await signer.address()
        let transaction = UnsignedTransaction(
            chainID: Deployment.chainID,
            from: address,
            to: EthereumAddress(trusted: Deployment.escrow),
            nonce: 4,
            gasLimit: 180_000,
            gasPrice: 1_000_000_000,
            data: Data([0x4f, 0x89, 0x6d, 0x4f])
        )

        let first = try await signer.sign(transaction)
        let second = try await signer.sign(transaction)
        let authorizationCount = await authorizer.authorizationCount()

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first, 0xf8)
        XCTAssertEqual(authorizationCount, 2)
    }

    func testSignsEIP712AuthorizationWithDeviceOwnerApproval() async throws {
        let authorizer = AllowingTransactionAuthorizer()
        let signer = TestnetLocalSigner(
            store: InMemorySecureDataStore(),
            authorizer: authorizer
        )
        let address = try await signer.address()
        let request = EvidenceAuthorizationRequest(
            action: .upload,
            paymentID: 11,
            walletAddress: address,
            chainID: Deployment.chainID,
            bodyHash: Data("evidence".utf8).keccak256Hash,
            nonce: ChainHash(trusted: "0x" + String(repeating: "00", count: 31) + "01"),
            expiresAt: 4_000_000_000
        )
        let payload = try request.typedDataJSON()

        let first = try await signer.signEIP712(payload)
        let second = try await signer.signEIP712(payload)
        let authorizationCount = await authorizer.authorizationCount()

        XCTAssertEqual(first.count, 65)
        XCTAssertEqual(first, second)
        XCTAssertEqual(authorizationCount, 2)
    }

    func testResetCreatesANewAccount() async throws {
        let signer = TestnetLocalSigner(
            store: InMemorySecureDataStore(),
            authorizer: AllowingTransactionAuthorizer()
        )
        let original = try await signer.address()

        try await signer.reset()
        let replacement = try await signer.address()

        XCTAssertNotEqual(replacement, original)
    }

    func testDeniedAuthorizationNeverLoadsSigningCredentials() async throws {
        let store = InMemorySecureDataStore()
        let signer = TestnetLocalSigner(
            store: store,
            authorizer: DenyingTransactionAuthorizer()
        )
        let address = try await signer.address()
        let loadsBeforeSigning = await store.loadCount()
        let transaction = UnsignedTransaction(
            chainID: Deployment.chainID,
            from: address,
            to: EthereumAddress(trusted: Deployment.escrow),
            nonce: 0,
            gasLimit: 100_000,
            gasPrice: 1,
            data: Data()
        )

        do {
            _ = try await signer.sign(transaction)
            XCTFail("Expected authorization denial")
        } catch {
            XCTAssertEqual(error as? TransactionAuthorizationError, .denied)
        }

        let loadsAfterSigning = await store.loadCount()
        XCTAssertEqual(loadsAfterSigning, loadsBeforeSigning)
    }
}

private actor InMemorySecureDataStore: SecureDataStore {
    private var values: [String: Data] = [:]
    private var loads = 0

    func save(_ data: Data, account: String) throws {
        values[account] = data
    }

    func load(account: String) throws -> Data? {
        loads += 1
        return values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }

    func accountCount() -> Int { values.count }
    func loadCount() -> Int { loads }
}

private actor AllowingTransactionAuthorizer: TransactionAuthorizing {
    private var count = 0

    func authorizeTransaction() async throws {
        count += 1
    }

    func authorizationCount() -> Int { count }
}

private struct DenyingTransactionAuthorizer: TransactionAuthorizing {
    func authorizeTransaction() async throws {
        throw TransactionAuthorizationError.denied
    }
}
