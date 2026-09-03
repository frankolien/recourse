import BigInt
import XCTest
@testable import Recourse

final class BundlerClientTests: XCTestCase {
    private let entryPoint = EthereumAddress(trusted: "0x0000000071727De22E5E9d8BAf0edAc6f37da032")
    private let safe = EthereumAddress(trusted: "0x93B5497A85be58436E6667140C9AaC7Fac9E5304")

    private func makeClient() -> (HTTPBundlerClient, BundlerStub) {
        let stub = BundlerStub()
        let client = HTTPBundlerClient(url: URL(string: "https://bundler.test/rpc")!, session: stub.session)
        return (client, stub)
    }

    private func operation() -> UserOperation {
        UserOperation(
            sender: safe,
            nonce: 7,
            callData: Data([0x7b, 0xb3, 0x74, 0x28]),
            callGasLimit: 0,
            verificationGasLimit: 0,
            preVerificationGas: 0,
            maxFeePerGas: 31_900_000_000,
            maxPriorityFeePerGas: 5_500_000_000,
            signature: Data(repeating: 0xff, count: 12)
        )
    }

    func testGasPriceReadsTheFastTier() async throws {
        let (client, stub) = makeClient()
        stub.respond(#"{"jsonrpc":"2.0","id":1,"result":{"slow":{"maxFeePerGas":"0x1","maxPriorityFeePerGas":"0x1"},"fast":{"maxFeePerGas":"0x76d635f00","maxPriorityFeePerGas":"0x147d35700"}}}"#)
        let price = try await client.gasPrice()
        XCTAssertEqual(price.maxFeePerGas, 31_900_000_000)
        XCTAssertEqual(price.maxPriorityFeePerGas, 5_500_000_000)
        XCTAssertEqual(stub.lastMethod, "pimlico_getUserOperationGasPrice")
    }

    func testEstimateSendsTheOperationAsHexFields() async throws {
        let (client, stub) = makeClient()
        stub.respond(#"{"jsonrpc":"2.0","id":1,"result":{"preVerificationGas":"0xc9a4","verificationGasLimit":"0x2258f","callGasLimit":"0xc404"}}"#)
        let gas = try await client.estimate(operation(), entryPoint: entryPoint)
        XCTAssertEqual(gas.preVerificationGas, 51_620)
        XCTAssertEqual(gas.verificationGasLimit, 140_687)
        XCTAssertEqual(gas.callGasLimit, 50_180)

        let params = try XCTUnwrap(stub.lastParams)
        let sent = try XCTUnwrap(params.first as? [String: String])
        XCTAssertEqual(sent["sender"], safe.value)
        XCTAssertEqual(sent["nonce"], "0x7")
        XCTAssertEqual(sent["callData"], "0x7bb37428")
        XCTAssertEqual(sent["maxFeePerGas"], "0x76d635f00")
        XCTAssertEqual(params.last as? String, entryPoint.value)
        XCTAssertNil(sent["paymaster"], "the account pays its own gas")
    }

    func testSendReturnsTheOperationHash() async throws {
        let (client, stub) = makeClient()
        stub.respond(#"{"jsonrpc":"2.0","id":1,"result":"0xabcf8d181fa29ac08b773370a9268ae826b76f01211b5b26736bee8bbc9c74e7"}"#)
        let hash = try await client.send(operation(), entryPoint: entryPoint)
        XCTAssertEqual(hash.value, "0xabcf8d181fa29ac08b773370a9268ae826b76f01211b5b26736bee8bbc9c74e7")
    }

    func testABundlerErrorSurfacesItsMessage() async throws {
        let (client, stub) = makeClient()
        stub.respond(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32500,"message":"UserOperation reverted during simulation with reason: AA24 signature error"}}"#)
        do {
            _ = try await client.send(operation(), entryPoint: entryPoint)
            XCTFail("expected the bundler's rejection")
        } catch {
            XCTAssertEqual(error as? BundlerError, .rejected("UserOperation reverted during simulation with reason: AA24 signature error"))
        }
    }

    func testAPendingReceiptIsNilNotAnError() async throws {
        let (client, stub) = makeClient()
        stub.respond(#"{"jsonrpc":"2.0","id":1,"result":null}"#)
        let receipt = try await client.receipt(operationHash: ChainHash(trusted: "0xabcf8d181fa29ac08b773370a9268ae826b76f01211b5b26736bee8bbc9c74e7"))
        XCTAssertNil(receipt)
    }

    func testAReceiptCarriesTheTransactionHashAndCost() async throws {
        let (client, stub) = makeClient()
        stub.respond(#"{"jsonrpc":"2.0","id":1,"result":{"success":true,"actualGasCost":"0x125d41d2ee6e00","actualGasUsed":"0x317e9","receipt":{"transactionHash":"0x2daf3d0b75cc9d00c35624e399243473769a2afb7503fafbec77d15aaaa74456"}}}"#)
        let receipt = try await client.receipt(operationHash: ChainHash(trusted: "0xabcf8d181fa29ac08b773370a9268ae826b76f01211b5b26736bee8bbc9c74e7"))
        XCTAssertEqual(receipt?.success, true)
        XCTAssertEqual(receipt?.transactionHash.value, "0x2daf3d0b75cc9d00c35624e399243473769a2afb7503fafbec77d15aaaa74456")
        XCTAssertEqual(receipt?.actualGasCost, BigUInt("125d41d2ee6e00", radix: 16))
    }
}

// MARK: - Stub

private final class BundlerStub: @unchecked Sendable {
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BundlerStubProtocol.self]
        session = URLSession(configuration: configuration)
        BundlerStubProtocol.reset()
    }

    deinit { BundlerStubProtocol.reset() }

    func respond(_ json: String) {
        BundlerStubProtocol.body = Data(json.utf8)
    }

    var lastMethod: String? { lastEnvelope?["method"] as? String }
    var lastParams: [Any]? { lastEnvelope?["params"] as? [Any] }

    private var lastEnvelope: [String: Any]? {
        guard let body = BundlerStubProtocol.requests.last else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}

private final class BundlerStubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests: [Data] = []

    static func reset() {
        body = Data()
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var collected = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            stream.close()
            Self.requests.append(collected)
        } else if let body = request.httpBody {
            Self.requests.append(body)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
