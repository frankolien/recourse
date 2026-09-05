import XCTest
@testable import Recourse

/// The service's shapes from `docs/treasury/11-service-api.md`, filled with values
/// that agree with each other: the typed data really hashes to `txHash` (viem's
/// `hashTypedData` said so, pinned in OlienSigningTests), the account's contract
/// signer is the test Safe, and the proposal is missing exactly that signer.
enum OlienFixture {
    static let olien = "0x0b1e2d3c4f5a6b7c8d9e0f1a2b3c4d5e6f708192"
    static let safe = "0x93b5497a85be58436e6667140c9aac7fac9e5304"
    static let safeSignerID = "0x00000000000000000000000093b5497a85be58436e6667140c9aac7fac9e5304"
    static let payee = "0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc"
    static let txHash = "0x9f1982e8aa339462b141e811c12a298347fd560a98f582a76d818f5223af7298"
    static let transferData = "0xa9059cbb0000000000000000000000009965507d1a55bcc2695c58ba16fb37d819b0a4dc000000000000000000000000000000000000000000000000000000000000c350"

    static let summaries = """
    [
      { "address": "\(olien)", "name": "Northwind treasury", "status": "live", "threshold": 2,
        "signerCount": 3, "usdcBalance": "1250000000", "openProposals": 1, "scheduledChanges": 0, "createdAt": 1788600000 }
    ]
    """

    static let account = """
    {
      "address": "\(olien)", "name": "Northwind treasury", "status": "live", "chainId": 5042002,
      "implementation": "0x1234567890123456789012345678901234567890", "implementationFrozen": false, "epoch": 1,
      "threshold": 2, "vetoThreshold": 0, "effectiveVetoThreshold": 1,
      "configDelay": 86400, "recoveryDelay": 86400, "recoveryCoSignDelay": 0,
      "signers": [
        { "signerId": "0x000000000000000000000000d6c574461d96ee708f58fe553049ad4f48bb983a", "kind": "ecdsa",
          "address": "0xd6c574461d96ee708f58fe553049ad4f48bb983a", "label": "Ada (Ledger)",
          "permissions": ["approve", "veto"], "since": 1, "mine": false },
        { "signerId": "\(safeSignerID)", "kind": "contract", "address": "\(safe)", "label": "Frank",
          "permissions": ["approve", "veto"], "since": 1, "mine": true },
        { "signerId": "0x1111111111111111111111111111111111111111111111111111111111111111", "kind": "webauthn",
          "address": null, "x": "0x22", "y": "0x33", "label": "Grace", "permissions": ["approve"], "since": 1, "mine": false }
      ],
      "usdcBalance": "1250000000", "entryPointDeposit": "0",
      "lanes": [{ "nonceKey": "0", "chainSequence": 4 }],
      "limits": [],
      "subAccounts": [],
      "createTx": "0xabc0000000000000000000000000000000000000000000000000000000000000", "createdAt": 1788600000,
      "membership": { "creator": false, "signerIds": ["\(safeSignerID)"] }
    }
    """

    static let proposal = """
    {
      "txHash": "\(txHash)", "account": "\(olien)",
      "nonceKey": "0", "sequence": 4, "nonce": "4", "epoch": 1,
      "kind": "transfer",
      "intent": { "recipients": [{ "to": "\(payee)", "amount": "50000", "label": "Payee", "memo": "Invoice 1042" }],
                  "token": "0x3600000000000000000000000000000000000000", "total": "50000" },
      "calls": [{ "to": "0x3600000000000000000000000000000000000000", "value": "0", "data": "\(transferData)" }],
      "decoded": [{ "to": "0x3600000000000000000000000000000000000000", "label": "USDC",
                    "summary": "transfer 0.05 USDC to \(payee) (Payee)", "selector": "0xa9059cbb", "readable": true }],
      "validAfter": 0, "validUntil": 1789200000,
      "path": "threshold",
      "status": "open",
      "confirmations": [{ "signerId": "0x000000000000000000000000d6c574461d96ee708f58fe553049ad4f48bb983a",
                          "address": "0xd6c574461d96ee708f58fe553049ad4f48bb983a", "label": "Ada (Ledger)",
                          "kind": "offchain", "signedAt": 1788600100 }],
      "required": 2, "approvals": 1,
      "missing": [{ "signerId": "\(safeSignerID)", "label": "Frank", "mine": true },
                  { "signerId": "0x1111111111111111111111111111111111111111111111111111111111111111", "label": "Grace", "mine": false }],
      "blockedBy": null,
      "hardRules": [],
      "simulation": { "ok": true, "error": null, "checkedAt": 1788600050 },
      "scheduledReadyAt": null, "scheduledWindowEndsAt": null, "scheduledExcluded": null,
      "vetoes": [], "effectiveVetoThreshold": 1,
      "executedTx": null, "executedAt": null,
      "proposer": { "accountId": 42, "name": "Ada" }, "createdAt": 1788600000,
      "typedData": {
        "domain": { "name": "Olien", "version": "1", "chainId": 5042002, "verifyingContract": "\(olien)" },
        "types": {
          "EIP712Domain": [{ "name": "name", "type": "string" }, { "name": "version", "type": "string" }, { "name": "chainId", "type": "uint256" }, { "name": "verifyingContract", "type": "address" }],
          "Call": [{ "name": "to", "type": "address" }, { "name": "value", "type": "uint256" }, { "name": "data", "type": "bytes" }],
          "Transaction": [{ "name": "nonce", "type": "uint256" }, { "name": "epoch", "type": "uint64" }, { "name": "calls", "type": "Call[]" }, { "name": "validAfter", "type": "uint48" }, { "name": "validUntil", "type": "uint48" }]
        },
        "primaryType": "Transaction",
        "message": { "nonce": "4", "epoch": 1, "calls": [{ "to": "0x3600000000000000000000000000000000000000", "value": "0", "data": "\(transferData)" }], "validAfter": 0, "validUntil": 1789200000 }
      }
    }
    """

    static let vetoCall = """
    { "to": "\(olien)", "data": "0xfb6f93f9\(txHash.dropFirst(2))", "signerIds": ["\(safeSignerID)"] }
    """

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

final class OlienAPIClientTests: XCTestCase {
    func testTheListRowDecodesWithItsBalanceInBaseUnits() throws {
        let rows = try OlienFixture.decode([OlienSummary].self, OlienFixture.summaries)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(row.displayName, "Northwind treasury")
        XCTAssertEqual(row.usdc, USDCAmount(baseUnits: 1_250_000_000))
        XCTAssertEqual(row.usdc.decimalString, "1250")
        XCTAssertEqual(row.openProposals, 1)
        XCTAssertEqual(row.shortAddress, "0x0b1e…8192")
    }

    func testTheAccountViewNamesEachSignerKindAsAWord() throws {
        let account = try OlienFixture.decode(OlienAccount.self, OlienFixture.account)
        XCTAssertEqual(account.signers.map(\.kindWord), ["Wallet", "Account", "Passkey"])
        XCTAssertEqual(account.threshold, 2)
        XCTAssertEqual(account.membership.signerIds, [OlienFixture.safeSignerID])
        // The Safe's row is the one the phone signs as, found by the padded id.
        let mine = try XCTUnwrap(account.signer(id: OlienFixture.safeSignerID.uppercased()))
        XCTAssertEqual(mine.label, "Frank")
        XCTAssertTrue(mine.canVeto)
        XCTAssertTrue(mine.mine)
        // A passkey signer has no address; the row still renders from its label.
        XCTAssertNil(account.signers[2].address)
        XCTAssertEqual(account.signers[2].displayName, "Grace")
        XCTAssertFalse(account.signers[2].canVeto)
    }

    func testTheProposalDecodesItsIntentApprovalsAndStatus() throws {
        let proposal = try OlienFixture.decode(OlienProposal.self, OlienFixture.proposal)
        XCTAssertEqual(proposal.status, .open)
        XCTAssertTrue(proposal.status.isActive)
        XCTAssertEqual(proposal.intentLine, "Send 0.05 USDC to Payee")
        XCTAssertEqual(proposal.memo, "Invoice 1042")
        XCTAssertEqual(proposal.approvalsText, "1 of 2")
        XCTAssertEqual(proposal.recipients.count, 1)
        XCTAssertEqual(proposal.recipients.first?.to, OlienFixture.payee)
        XCTAssertTrue(proposal.isMissing(OlienFixture.safeSignerID))
        XCTAssertFalse(proposal.hasConfirmation(from: OlienFixture.safeSignerID))
        XCTAssertTrue(proposal.hasConfirmation(from: "0x000000000000000000000000D6C574461D96EE708F58FE553049AD4F48BB983A"))
        XCTAssertNil(proposal.scheduledReadyDate)
        XCTAssertEqual(proposal.proposer?.name, "Ada")
        XCTAssertEqual(proposal.decoded.first?.selector, "0xa9059cbb")
    }

    func testAStatusTheServiceAddsLaterDecodesAsUnknownRatherThanFailing() throws {
        let json = OlienFixture.proposal.replacingOccurrences(of: "\"status\": \"open\"", with: "\"status\": \"paused\"")
        let proposal = try OlienFixture.decode(OlienProposal.self, json)
        XCTAssertEqual(proposal.status, .unknown)
        XCTAssertFalse(proposal.status.isActive)
    }

    func testTypedDataKeepsItsIntegersThroughAReserialisation() throws {
        // A `1` that came back as `1.0` would still parse and hash to something else,
        // which is the quiet kind of wrong. The re-serialised JSON must carry the
        // same tokens the service sent.
        let proposal = try OlienFixture.decode(OlienProposal.self, OlienFixture.proposal)
        let json = try XCTUnwrap(String(data: proposal.typedDataJSON(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"chainId\":5042002"), json)
        XCTAssertTrue(json.contains("\"epoch\":1"), json)
        XCTAssertTrue(json.contains("\"nonce\":\"4\""), json)
        XCTAssertTrue(json.contains("\"validUntil\":1789200000"), json)
        XCTAssertFalse(json.contains(".0"), json)
    }

    func testTheVetoCallDecodes() throws {
        let call = try OlienFixture.decode(VetoCall.self, OlienFixture.vetoCall)
        XCTAssertEqual(call.to, OlienFixture.olien)
        XCTAssertEqual(call.signerIds, [OlienFixture.safeSignerID])
        XCTAssertEqual(call.data.count, 2 + 8 + 64)
    }

    // MARK: The requests

    func testListingSendsTheBearerToTheTreasuryRoute() async throws {
        let stub = OlienStubbedTransport()
        stub.respond(json: OlienFixture.summaries)
        let client = OlienAPIClient(baseURL: baseURL, session: stub.session)

        let rows = try await client.accounts(accessToken: "token-1")

        XCTAssertEqual(rows.count, 1)
        let request = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(request.url?.path(), "/api/treasury/accounts")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
    }

    func testAStatusFilterBecomesOneCommaSeparatedQuery() async throws {
        let stub = OlienStubbedTransport()
        stub.respond(json: "[]")
        let client = OlienAPIClient(baseURL: baseURL, session: stub.session)

        _ = try await client.proposals(account: OlienFixture.olien.uppercased(), statuses: ["open", "ready"], accessToken: "t")

        let request = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(request.url?.path(), "/api/treasury/accounts/\(OlienFixture.olien)/proposals")
        XCTAssertEqual(request.url?.query(), "status=open,ready")
    }

    func testAConfirmationPostsTheSignerIdAndSignatureAsTheDocSpells() async throws {
        let stub = OlienStubbedTransport()
        stub.respond(json: OlienFixture.proposal)
        let client = OlienAPIClient(baseURL: baseURL, session: stub.session)

        _ = try await client.confirm(
            account: OlienFixture.olien,
            txHash: OlienFixture.txHash,
            signerID: OlienFixture.safeSignerID,
            signature: "0xdeadbeef",
            accessToken: "t"
        )

        let request = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path(), "/api/treasury/accounts/\(OlienFixture.olien)/proposals/\(OlienFixture.txHash)/confirmations")
        let body = try XCTUnwrap(stub.bodies.last)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(fields, ["signerId": OlienFixture.safeSignerID, "signature": "0xdeadbeef"])
    }

    func testTheVetoCallAndScheduledExecuteUseTheScheduledRoutes() async throws {
        let stub = OlienStubbedTransport()
        stub.respond(json: OlienFixture.vetoCall)
        let client = OlienAPIClient(baseURL: baseURL, session: stub.session)

        _ = try await client.vetoCall(account: OlienFixture.olien, txHash: OlienFixture.txHash, accessToken: "t")
        XCTAssertEqual(
            stub.requests.last?.url?.path(),
            "/api/treasury/accounts/\(OlienFixture.olien)/scheduled/\(OlienFixture.txHash)/veto-call"
        )

        stub.respond(json: OlienFixture.proposal)
        _ = try await client.executeScheduled(account: OlienFixture.olien, txHash: OlienFixture.txHash, accessToken: "t")
        XCTAssertEqual(stub.requests.last?.httpMethod, "POST")
        XCTAssertEqual(
            stub.requests.last?.url?.path(),
            "/api/treasury/accounts/\(OlienFixture.olien)/scheduled/\(OlienFixture.txHash)/execute"
        )
    }

    func testARefusalCarriesTheServicesOwnWords() async {
        let stub = OlienStubbedTransport()
        stub.respond(json: #"{"error":"the proposal is executed, not ready"}"#, status: 409)
        let client = OlienAPIClient(baseURL: baseURL, session: stub.session)
        do {
            _ = try await client.execute(account: OlienFixture.olien, txHash: OlienFixture.txHash, accessToken: "t")
            XCTFail("expected a refusal")
        } catch let error as OlienAPIError {
            XCTAssertEqual(error, .rejected(status: 409, message: "the proposal is executed, not ready"))
            XCTAssertEqual(error.message, "the proposal is executed, not ready")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private var baseURL: URL { URL(string: "https://example.invalid")! }
}

/// A URLSession that answers from memory and keeps every request it was handed.
final class OlienStubbedTransport: @unchecked Sendable {
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OlienStubProtocol.self]
        session = URLSession(configuration: configuration)
        OlienStubProtocol.reset()
    }

    deinit {
        OlienStubProtocol.reset()
    }

    func respond(json: String, status: Int = 200) {
        OlienStubProtocol.body = Data(json.utf8)
        OlienStubProtocol.status = status
    }

    var requests: [URLRequest] { OlienStubProtocol.requests }
    var bodies: [Data] { OlienStubProtocol.bodies }
}

private final class OlienStubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data("[]".utf8)
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func reset() {
        body = Data("[]".utf8)
        status = 200
        requests = []
        bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        // URLProtocol strips httpBody off the request it hands back; the body stream
        // is where the payload survives.
        if let stream = request.httpBodyStream {
            stream.open()
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(contentsOf: buffer[0 ..< read])
            }
            stream.close()
            Self.bodies.append(collected)
        } else if let body = request.httpBody {
            Self.bodies.append(body)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
