import XCTest
@preconcurrency import web3swift
@testable import Recourse

final class EvidenceAPIClientTests: XCTestCase {
    func testAuthorizationDigestMatchesBackendAndViemGolden() throws {
        let request = EvidenceAuthorizationRequest(
            action: .manifest,
            paymentID: 10,
            walletAddress: EthereumAddress(trusted: "0x00000000000000000000000000000000000000ab"),
            chainID: 5_042_002,
            bodyHash: ChainHash(trusted: "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"),
            nonce: ChainHash(trusted: "0x" + String(repeating: "00", count: 31) + "ff"),
            expiresAt: 4_000_000_000
        )

        XCTAssertEqual(
            try request.digest(),
            ChainHash(trusted: "0xab9ccaee667c989b0f204c16aa493a357f48a6ad44e3c7c161a69a543654ad7a")
        )
    }

    func testUploadSignsExactBytesAndVerifiesStoredHash() async throws {
        let body = Data("proof of delivery".utf8)
        let storedHash = body.keccak256Hash
        let transport = FixtureEvidenceTransport(responses: [
            .json(200, Self.challengeJSON),
            .json(200, """
            {"hash":"\(storedHash.value)","size":\(body.count),"contentType":"text/plain"}
            """)
        ])
        let signer = FixtureAuthorizationSigner()
        let client = EvidenceAPIClient(
            baseURL: URL(string: "https://api.recourse.test/")!,
            chainID: Deployment.chainID,
            signer: signer,
            transport: transport
        )

        let uploaded = try await client.upload(
            EvidenceDraft(kind: .description, content: body),
            paymentID: 11
        )

        XCTAssertEqual(uploaded.kind, .description)
        XCTAssertEqual(uploaded.hash, storedHash)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.path), ["api/auth/challenge", "api/evidence"])
        XCTAssertEqual(requests[1].body, body)
        XCTAssertEqual(requests[1].headers["Content-Type"], "text/plain; charset=utf-8")

        let envelope = try Self.decodeAuthHeader(requests[1])
        XCTAssertEqual(envelope["action"] as? String, "evidence.upload")
        XCTAssertEqual(envelope["paymentId"] as? Int, 11)
        XCTAssertEqual(envelope["bodyHash"] as? String, storedHash.value)
        XCTAssertEqual(envelope["nonce"] as? String, Self.nonce)
        XCTAssertEqual(envelope["walletAddress"] as? String, DomainFixture.buyer.value)

        let recordedTypedData = await signer.lastTypedData()
        let typedData = try XCTUnwrap(recordedTypedData)
        let authorization = try EIP712Parser.parse(typedData)
        let expectedAuthorization = EvidenceAuthorizationRequest(
            action: .upload,
            paymentID: 11,
            walletAddress: DomainFixture.buyer,
            chainID: Deployment.chainID,
            bodyHash: storedHash,
            nonce: ChainHash(trusted: Self.nonce),
            expiresAt: 4_000_000_000
        )
        XCTAssertEqual(
            try ChainHash(authorization.signHash().hexEncoded),
            try expectedAuthorization.digest()
        )
    }

    func testManifestSignsTheExactJSONBodySentToBackend() async throws {
        let root = "0x" + String(repeating: "44", count: 32)
        let transport = FixtureEvidenceTransport(responses: [
            .json(200, Self.challengeJSON),
            .json(200, """
            {"paymentId":11,"matches":true,"computedRoot":"\(root)","onchainRoot":"\(root)","items":[]}
            """)
        ])
        let client = EvidenceAPIClient(
            baseURL: URL(string: "https://api.recourse.test/")!,
            chainID: Deployment.chainID,
            signer: FixtureAuthorizationSigner(),
            transport: transport
        )
        let evidence = [
            UploadedEvidence(
                kind: .photo,
                hash: ChainHash(trusted: "0x" + String(repeating: "12", count: 32))
            ),
            UploadedEvidence(
                kind: .description,
                hash: ChainHash(trusted: "0x" + String(repeating: "34", count: 32))
            )
        ]

        let receipt = try await client.publishManifest(paymentID: 11, evidence: evidence)

        XCTAssertTrue(receipt.matches)
        XCTAssertEqual(receipt.computedRoot.value, root)
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.last)
        let manifest = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        XCTAssertEqual(manifest?["paymentId"] as? Int, 11)
        let items = manifest?["items"] as? [[String: Any]]
        XCTAssertEqual(items?.map { $0["evType"] as? Int }, [1, 2])
        let envelope = try Self.decodeAuthHeader(request)
        XCTAssertEqual(envelope["action"] as? String, "evidence.manifest")
        XCTAssertEqual(envelope["bodyHash"] as? String, request.body.keccak256Hash.value)
    }

    func testUploadRejectsBackendHashMismatch() async throws {
        let transport = FixtureEvidenceTransport(responses: [
            .json(200, Self.challengeJSON),
            .json(200, """
            {"hash":"0x\(String(repeating: "99", count: 32))","size":3,"contentType":"image/jpeg"}
            """)
        ])
        let client = EvidenceAPIClient(
            baseURL: URL(string: "https://api.recourse.test/")!,
            chainID: Deployment.chainID,
            signer: FixtureAuthorizationSigner(),
            transport: transport
        )

        do {
            _ = try await client.upload(
                EvidenceDraft(kind: .photo, content: Data([1, 2, 3])),
                paymentID: 11
            )
            XCTFail("Expected hash mismatch")
        } catch {
            guard case EvidenceAPIError.evidenceHashMismatch = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    private static func decodeAuthHeader(_ request: EvidenceHTTPRequest) throws -> [String: Any] {
        let encoded = try XCTUnwrap(request.headers["X-Recourse-Auth"])
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private extension EvidenceAPIClientTests {
    static let nonce = "0x" + String(repeating: "00", count: 31) + "ff"
    static let challengeJSON = """
    {"nonce":"\(nonce)","expiresAt":4000000000,"ttlSecs":300}
    """
}

private actor FixtureAuthorizationSigner: BuyerSigner {
    private var typedData: Data?

    func address() async throws -> EthereumAddress { DomainFixture.buyer }
    func sign(_ transaction: UnsignedTransaction) async throws -> Data { Data([0xaa]) }

    func signEIP712(_ typedData: Data) async throws -> Data {
        self.typedData = typedData
        return Data(repeating: 0xab, count: 65)
    }

    func reset() async throws {}
    func lastTypedData() -> Data? { typedData }
}

private actor FixtureEvidenceTransport: EvidenceAPITransport {
    private var queuedResponses: [EvidenceHTTPResponse]
    private var recordedRequests: [EvidenceHTTPRequest] = []

    init(responses: [EvidenceHTTPResponse]) {
        queuedResponses = responses
    }

    func execute(_ request: EvidenceHTTPRequest, baseURL: URL) async throws -> EvidenceHTTPResponse {
        recordedRequests.append(request)
        guard !queuedResponses.isEmpty else { throw EvidenceAPIError.invalidResponse }
        return queuedResponses.removeFirst()
    }

    func requests() -> [EvidenceHTTPRequest] { recordedRequests }
}

private extension EvidenceHTTPResponse {
    static func json(_ statusCode: Int, _ json: String) -> EvidenceHTTPResponse {
        EvidenceHTTPResponse(statusCode: statusCode, body: Data(json.utf8))
    }
}
