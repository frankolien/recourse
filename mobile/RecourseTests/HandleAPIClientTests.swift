import XCTest
@testable import Recourse

final class HandleAPIClientTests: XCTestCase {
    func testStripsTheAtSignBeforeItReachesAURLPath() {
        // The server accepts a leading @ and so does the field, but putting one in a
        // URL path is an encoding bug waiting for a character that means nothing.
        XCTAssertEqual(HandleAPIClient.strip("@frank"), "frank")
        XCTAssertEqual(HandleAPIClient.strip("  @frank  "), "frank")
        XCTAssertEqual(HandleAPIClient.strip("frank"), "frank")
        XCTAssertEqual(HandleAPIClient.strip("@@frank"), "frank")
    }

    func testUnclaimedIsItsOwnCaseRatherThanAGenericFailure() {
        // The same 404 means "cannot send" when paying and "yours to take" when
        // choosing a name, so the caller has to be able to tell it apart.
        XCTAssertEqual(HandleAPIError.unclaimed.message, "No one is using that name.")
        XCTAssertNotEqual(
            HandleAPIError.unclaimed,
            HandleAPIError.rejected(status: 404, message: "no such handle")
        )
    }

    func testARefusalShowsTheServersOwnWordsRatherThanAStatusCode() {
        let error = HandleAPIError.rejected(status: 409, message: "that handle is taken")
        XCTAssertEqual(error.message, "that handle is taken")
    }

    // MARK: Naming addresses

    func testNamingNothingAsksTheServerNothing() async throws {
        let stub = StubbedTransport()
        let client = HandleAPIClient(baseURL: baseURL, session: stub.session)

        let found = try await client.names(for: [])

        XCTAssertTrue(found.isEmpty)
        // A request here would be a round trip to learn what the caller already knows.
        XCTAssertEqual(stub.requestCount, 0)
    }

    func testTheSameAddressInAnyCasingIsAskedForOnce() async throws {
        let stub = StubbedTransport()
        stub.respond(json: "[]")
        let client = HandleAPIClient(baseURL: baseURL, session: stub.session)

        _ = try await client.names(
            for: [
                "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A",
                "0xd6c574461d96ee708f58fe553049ad4f48bb983a",
                "0xD6C574461D96EE708F58FE553049AD4F48BB983A",
            ]
        )

        // One address, one entry. A list of cheques is full of repeats, and asking the
        // directory about the same person three times is three times the work for the
        // same answer.
        let asked = try XCTUnwrap(stub.lastBodyAddresses)
        XCTAssertEqual(asked, ["0xd6c574461d96ee708f58fe553049ad4f48bb983a"])
    }

    func testMoreAddressesThanTheServerAcceptsAreCappedRatherThanRefused() async throws {
        let stub = StubbedTransport()
        stub.respond(json: "[]")
        let client = HandleAPIClient(baseURL: baseURL, session: stub.session)

        // The server rejects more than fifty outright. Sending sixty would fail the
        // whole lookup and leave every row on screen showing hex, so the client trims.
        let many = (0..<60).map { String(format: "0x%040x", $0) }
        _ = try await client.names(for: many)

        let asked = try XCTUnwrap(stub.lastBodyAddresses)
        XCTAssertEqual(asked.count, 50)
    }

    func testNamesComeBackKeyedLowercaseSoAChecksummedAddressStillMatches() async throws {
        let stub = StubbedTransport()
        // The directory stores whatever casing was claimed, so it can answer with a
        // checksummed address while every caller compares lowercase.
        stub.respond(json: """
        [{"handle":"Frank","address":"0xD6c574461d96Ee708f58Fe553049aD4f48BB983A"}]
        """)
        let client = HandleAPIClient(baseURL: baseURL, session: stub.session)

        let found = try await client.names(for: ["0xd6c574461d96ee708f58fe553049ad4f48bb983a"])

        XCTAssertEqual(found["0xd6c574461d96ee708f58fe553049ad4f48bb983a"], "Frank")
        // Display casing is preserved: the owner chose it and the payer should see it.
        XCTAssertEqual(found.count, 1)
    }

    func testAnAddressNobodyClaimedIsSimplyAbsent() async throws {
        let stub = StubbedTransport()
        stub.respond(json: """
        [{"handle":"Frank","address":"0xd6c574461d96ee708f58fe553049ad4f48bb983a"}]
        """)
        let client = HandleAPIClient(baseURL: baseURL, session: stub.session)

        let found = try await client.names(
            for: [
                "0xd6c574461d96ee708f58fe553049ad4f48bb983a",
                "0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc",
            ]
        )

        // Absent rather than empty-string, so a caller can fall back to the shortened
        // address instead of rendering a blank name.
        XCTAssertNil(found["0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc"])
    }

    private var baseURL: URL { URL(string: "https://example.invalid")! }
}

/// A URLSession that answers from memory and remembers what it was asked.
///
/// The interesting part of `names(for:)` is the request it builds, not the decode: the
/// deduplication and the cap both happen before anything is sent, and both fail
/// silently in production if they regress.
private final class StubbedTransport: @unchecked Sendable {
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
        StubProtocol.reset()
    }

    deinit {
        StubProtocol.reset()
    }

    func respond(json: String) {
        StubProtocol.body = Data(json.utf8)
    }

    var requestCount: Int { StubProtocol.requests.count }

    /// The addresses of the most recent request, in the order they were sent.
    var lastBodyAddresses: [String]? {
        guard let body = StubProtocol.requests.last,
              let decoded = try? JSONDecoder().decode(Payload.self, from: body) else { return nil }
        return decoded.addresses.sorted()
    }

    private struct Payload: Decodable { let addresses: [String] }
}

private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data("[]".utf8)
    nonisolated(unsafe) static var requests: [Data] = []

    static func reset() {
        body = Data("[]".utf8)
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol strips httpBody off the request it hands back, so the only place
        // the payload survives is the body stream.
        if let stream = request.httpBodyStream {
            stream.open()
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(contentsOf: buffer[0..<read])
            }
            stream.close()
            Self.requests.append(collected)
        } else if let body = request.httpBody {
            Self.requests.append(body)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
