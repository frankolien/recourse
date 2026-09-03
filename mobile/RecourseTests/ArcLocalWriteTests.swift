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

    /// A cheque signed by the app, cashed by the app, against a token that enforces
    /// EIP-3009.
    ///
    /// The engine suite already proves a signed cheque cashes, but it signs with viem.
    /// Nothing there exercises the path that actually ships: Web3Signer parsing the
    /// typed data this app builds, the recovery id being normalized to 27 or 28, and
    /// transferWithAuthorization being ABI encoded by ArcContractWriter. Each of those
    /// fails the same way, with a signature that looks fine on the device and is
    /// refused when someone tries to take their money.
    func testAChequeSignedByTheAppCashesAndCanBeVoided() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MOBILE_LOCAL_WRITE_TESTS"] == "1" else {
            throw XCTSkip("Set MOBILE_LOCAL_WRITE_TESTS=1 through mobile/scripts/verify_local_writes.sh")
        }
        guard let deploymentPath = environment["MOBILE_LOCAL_DEPLOYMENT"],
              let seedPath = environment["MOBILE_LOCAL_SEED"],
              let rpcValue = environment["MOBILE_LOCAL_RPC_URL"],
              let rpcURL = URL(string: rpcValue),
              let privateKey = environment["MOBILE_LOCAL_BUYER_PK"],
              let chequeToken = environment["MOBILE_LOCAL_CHEQUE_TOKEN"] else {
            XCTFail("Local write test environment is incomplete")
            return
        }

        let deployment = try decode(LocalDeployment.self, path: deploymentPath)
        let seed = try decode(LocalSeed.self, path: seedPath)
        // Same deployment, except USDC points at the EIP-3009 token the harness put up.
        // Everything else in the app reads its token address from configuration, so this
        // is the whole of the substitution.
        let configuration = try deployment.configuration(rpcURL: rpcURL, usdcOverride: chequeToken)

        let store = LocalSecureDataStore()
        try await preloadSigner(store: store, privateKey: privateKey)
        let signer = TestnetLocalSigner(store: store, authorizer: LocalAllowingAuthorizer())
        let writer = try await signer.address()
        let recipient = try EthereumAddress(seed.merchant)

        let gateway = try ArcContractGateway.live(configuration: configuration, signer: signer)

        // The app derives the domain separator offline so a cheque can be written with
        // no network. If that derivation is wrong every signature below is worthless.
        let onChain = try await Self.domainSeparator(
            token: configuration.usdcAddress,
            rpcURL: rpcURL
        )
        XCTAssertEqual(
            ChequeAuthorization.domainSeparator(
                token: configuration.usdcAddress,
                chainID: Int(configuration.chainID)
            ),
            onChain
        )

        let amount = USDCAmount(baseUnits: 2_500_000)
        let cheque = Cheque(
            from: writer,
            to: recipient,
            amount: amount,
            validAfter: 0,
            validBefore: UInt64(Date().timeIntervalSince1970) + 3_600,
            nonce: Cheque.randomNonce()
        )
        let signature = try await signer.signEIP712(
            ChequeAuthorization.typedData(
                for: cheque,
                token: configuration.usdcAddress,
                chainID: Int(configuration.chainID)
            )
        )

        let writerBefore = try await gateway.usdcBalance(of: writer)
        let recipientBefore = try await gateway.usdcBalance(of: recipient)
        let unspent = try await gateway.authorizationState(authorizer: writer, nonce: cheque.nonce)
        XCTAssertFalse(unspent)

        // Submitted by the writer's own wallet, paying to someone else. That is the
        // not-bearer property proven through the app's code: whoever submits it, the
        // token moves the money to the address that was signed over.
        let cashHash = try await gateway.cashCheque(cheque, signature: signature)
        let cashReceipt = try await gateway.waitForReceipt(transactionHash: cashHash)
        XCTAssertEqual(cashReceipt.outcome, .confirmed)

        let recipientAfter = try await gateway.usdcBalance(of: recipient)
        let writerAfter = try await gateway.usdcBalance(of: writer)
        XCTAssertEqual(recipientAfter.baseUnits - recipientBefore.baseUnits, amount.baseUnits)
        XCTAssertEqual(writerAfter.baseUnits, writerBefore.baseUnits - amount.baseUnits)
        let spent = try await gateway.authorizationState(authorizer: writer, nonce: cheque.nonce)
        XCTAssertTrue(spent, "the nonce must be spent, which is what stops a second cash")

        // A second cheque, voided instead. The cancellation is a different EIP-712
        // struct, so this proves the app builds that one correctly too.
        let doomed = Cheque(
            from: writer,
            to: recipient,
            amount: USDCAmount(baseUnits: 900_000),
            validAfter: 0,
            validBefore: UInt64(Date().timeIntervalSince1970) + 3_600,
            nonce: Cheque.randomNonce()
        )
        let doomedSignature = try await signer.signEIP712(
            ChequeAuthorization.typedData(
                for: doomed,
                token: configuration.usdcAddress,
                chainID: Int(configuration.chainID)
            )
        )
        let cancellation = try await signer.signEIP712(
            ChequeAuthorization.cancellationTypedData(
                authorizer: writer,
                nonce: doomed.nonce,
                token: configuration.usdcAddress,
                chainID: Int(configuration.chainID)
            )
        )
        let voidHash = try await gateway.voidCheque(
            nonce: doomed.nonce,
            cancellationSignature: cancellation
        )
        let voidReceipt = try await gateway.waitForReceipt(transactionHash: voidHash)
        XCTAssertEqual(voidReceipt.outcome, .confirmed)
        let burned = try await gateway.authorizationState(authorizer: writer, nonce: doomed.nonce)
        XCTAssertTrue(burned)

        // And the cheque the recipient is holding is now worthless, which is the only
        // thing voiding is for.
        // It fails at gas estimation rather than on chain, so whoever tries to cash a
        // voided cheque pays nothing to find out.
        let afterVoid = try await gateway.usdcBalance(of: recipient)
        do {
            _ = try await gateway.cashCheque(doomed, signature: doomedSignature)
            XCTFail("a voided cheque must not be submittable")
        } catch {
            let unchanged = try await gateway.usdcBalance(of: recipient)
            XCTAssertEqual(unchanged, afterVoid)
        }
    }

    /// Read straight over JSON-RPC. The app has no reason to call DOMAIN_SEPARATOR in
    /// production, so it is not on the gateway, and adding it there to satisfy a test
    /// would be widening the surface for the test's benefit.
    private static func domainSeparator(
        token: Recourse.EthereumAddress,
        rpcURL: URL
    ) async throws -> Data {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_call",
            "params": [
                // keccak256("DOMAIN_SEPARATOR()")[0..4]
                ["to": token.value, "data": "0x3644e515"],
                "latest",
            ],
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? String)
        return Data(hex: String(result.dropFirst(2)))
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

    func configuration(rpcURL: URL, usdcOverride: String? = nil) throws -> AppConfiguration {
        AppConfiguration(
            rpcURL: rpcURL,
            chainID: chainId,
            chainName: "Anvil",
            escrowAddress: try EthereumAddress(escrow),
            policyRegistryAddress: try EthereumAddress(policyRegistry),
            settlementVaultAddress: try EthereumAddress(settlementVault),
            usdcAddress: try EthereumAddress(usdcOverride ?? usdc)
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
