import XCTest
@preconcurrency import Web3Core
@preconcurrency import web3swift
@testable import Recourse

final class ArcLocalWriteTests: XCTestCase {
    func testApprovePayDisputeAndResolveAgainstAnvil() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MOBILE_LOCAL_WRITE_TESTS"] == "1" else {
            throw XCTSkip("Set MOBILE_LOCAL_WRITE_TESTS=1 through mobile/scripts/verify_local_writes.sh")
        }
        guard let deploymentPath = environment["MOBILE_LOCAL_DEPLOYMENT"],
              let seedPath = environment["MOBILE_LOCAL_SEED"],
              let rpcValue = environment["MOBILE_LOCAL_RPC_URL"],
              let rpcURL = URL(string: rpcValue),
              let privateKey = environment["MOBILE_LOCAL_BUYER_PK"] else {
            XCTFail("Local write test environment is incomplete")
            return
        }

        let deployment = try decode(LocalDeployment.self, path: deploymentPath)
        let seed = try decode(LocalSeed.self, path: seedPath)
        let configuration = try deployment.configuration(rpcURL: rpcURL)
        let store = LocalSecureDataStore()
        try await preloadSigner(store: store, privateKey: privateKey)
        let signer = TestnetLocalSigner(
            store: store,
            authorizer: LocalAllowingAuthorizer()
        )
        let buyer = try await signer.address()
        XCTAssertEqual(buyer.value.lowercased(), seed.buyer.lowercased())

        let gateway = try ArcContractGateway.live(
            configuration: configuration,
            signer: signer
        )
        let startingBalance = try await gateway.usdcBalance(of: buyer)
        let amount = USDCAmount(baseUnits: 250_000)

        let approvalHash = try await gateway.approveUSDC(amount: amount)
        let approvalReceipt = try await gateway.waitForReceipt(transactionHash: approvalHash)
        XCTAssertEqual(approvalReceipt.outcome, .confirmed)

        let request = PaymentRequest(
            version: 1,
            chainID: configuration.chainID,
            escrow: configuration.escrowAddress,
            policyID: seed.policyID,
            merchant: try EthereumAddress(seed.merchant),
            amount: amount,
            orderReference: ChainHash(trusted: "0x" + String(repeating: "42", count: 32))
        )
        let paymentHash = try await gateway.pay(request)
        let paymentReceipt = try await gateway.waitForReceipt(transactionHash: paymentHash)
        XCTAssertEqual(paymentReceipt.outcome, .confirmed)
        let paymentID = try XCTUnwrap(paymentReceipt.paymentID)

        let paid = try await gateway.payment(id: paymentID)
        XCTAssertEqual(paid.buyer, buyer)
        XCTAssertEqual(paid.merchant.value.lowercased(), seed.merchant.lowercased())
        XCTAssertEqual(paid.amount, amount)
        XCTAssertEqual(paid.status, .paid)

        let evidence = UploadedEvidence(
            kind: .photo,
            hash: ChainHash(trusted: "0x" + String(repeating: "cd", count: 32))
        )
        let disputeHash = try await gateway.fileDispute(
            paymentID: paymentID,
            claimType: .damaged,
            evidence: [evidence]
        )
        let disputeReceipt = try await gateway.waitForReceipt(transactionHash: disputeHash)
        XCTAssertEqual(disputeReceipt.outcome, .confirmed)

        let disputed = try await gateway.payment(id: paymentID)
        XCTAssertEqual(disputed.status, .disputed)
        XCTAssertEqual(disputed.claimType, .damaged)
        XCTAssertEqual(disputed.evidenceMask, UInt16(EvidenceKind.photo.rawValue))

        let preview = try await gateway.previewVerdict(paymentID: paymentID)
        XCTAssertEqual(preview.refundBPS, 10_000)
        XCTAssertTrue(preview.matched)

        let resolutionHash = try await gateway.resolve(paymentID: paymentID)
        let resolutionReceipt = try await gateway.waitForReceipt(transactionHash: resolutionHash)
        XCTAssertEqual(resolutionReceipt.outcome, .confirmed)

        let settled = try await gateway.payment(id: paymentID)
        let endingBalance = try await gateway.usdcBalance(of: buyer)
        XCTAssertEqual(settled.status, .settled)
        XCTAssertEqual(settled.verdictBPS, 10_000)
        XCTAssertEqual(endingBalance, startingBalance)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, path: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private func preloadSigner(
        store: LocalSecureDataStore,
        privateKey: String
    ) async throws {
        let password = "anvil-mobile-write-test"
        let value = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
        let keystore = try XCTUnwrap(
            try EthereumKeystoreV3(privateKey: Data(hex: value), password: password)
        )
        let serialized = try XCTUnwrap(try keystore.serialize())
        try await store.save(serialized, account: TestnetLocalSigner.AccountKey.keystore)
        try await store.save(Data(password.utf8), account: TestnetLocalSigner.AccountKey.password)
    }
}

private struct LocalDeployment: Decodable {
    let chainId: UInt64
    let escrow: String
    let policyRegistry: String
    let settlementVault: String
    let usdc: String

    func configuration(rpcURL: URL) throws -> AppConfiguration {
        AppConfiguration(
            rpcURL: rpcURL,
            chainID: chainId,
            chainName: "Anvil",
            escrowAddress: try EthereumAddress(escrow),
            policyRegistryAddress: try EthereumAddress(policyRegistry),
            settlementVaultAddress: try EthereumAddress(settlementVault),
            usdcAddress: try EthereumAddress(usdc)
        )
    }
}

private struct LocalSeed: Decodable {
    let policyID: UInt64
    let merchant: String
    let buyer: String

    enum CodingKeys: String, CodingKey {
        case policyID = "policyId"
        case merchant, buyer
    }
}

private actor LocalSecureDataStore: SecureDataStore {
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        values[account] = data
    }

    func load(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}

private struct LocalAllowingAuthorizer: TransactionAuthorizing {
    func authorizeTransaction() async throws {}
}
