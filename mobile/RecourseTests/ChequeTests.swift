import XCTest
@testable import Recourse

final class ChequeTests: XCTestCase {
    private let usdc = EthereumAddress(trusted: "0x3600000000000000000000000000000000000000")
    private let chainID = 5042002

    /// Fixed inputs whose digest was computed independently with cast, so a change to
    /// the encoding here fails loudly instead of producing a signature the token
    /// silently refuses when someone tries to cash the cheque.
    private var goldenCheque: Cheque {
        Cheque(
            from: EthereumAddress(trusted: "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A"),
            to: EthereumAddress(trusted: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"),
            amount: USDCAmount(baseUnits: 1_500_000),
            validAfter: 0,
            validBefore: 2_000_000_000,
            nonce: Data(repeating: 0x11, count: 32)
        )
    }

    private func hex(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    func testDomainSeparatorMatchesTheLiveArcUSDCContract() {
        // Read from 0x3600...0000 on Arc testnet with cast. Deriving it locally is what
        // lets a cheque be written offline, so it has to agree with the token exactly.
        XCTAssertEqual(
            hex(ChequeAuthorization.domainSeparator(token: usdc, chainID: chainID)),
            "0x361191522483d32a83e70ae7183b4b9629442c13a78bc9921d6f707911c8c6b0"
        )
    }

    func testStructHashMatchesTheIndependentlyComputedValue() {
        XCTAssertEqual(
            hex(ChequeAuthorization.structHash(for: goldenCheque)),
            "0xb9d39c1041cf37515b4eecf5486d6bb6ffa26cf81880c1fb360889c3d1049f25"
        )
    }

    func testDigestMatchesTheIndependentlyComputedValue() {
        // The one number that decides whether a cheque can ever be cashed.
        XCTAssertEqual(
            hex(ChequeAuthorization.digest(for: goldenCheque, token: usdc, chainID: chainID)),
            "0x6cce28229ed8f091ce5d706f78c015497cf66db524fdd86919cfb877f4fa59b4"
        )
    }

    func testTheTypeHashesAreTheStandardOnes() {
        // Pinned as strings in the source, so they are asserted rather than trusted.
        XCTAssertEqual(
            ChequeAuthorization.typeHash,
            "7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267"
        )
        XCTAssertEqual(
            ChequeAuthorization.domainTypeHash,
            "8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f"
        )
    }

    func testTypedDataCarriesEverythingTheDigestCommitsTo() throws {
        let data = try ChequeAuthorization.typedData(for: goldenCheque, token: usdc, chainID: chainID)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["primaryType"] as? String, "TransferWithAuthorization")

        let domain = try XCTUnwrap(json["domain"] as? [String: Any])
        XCTAssertEqual(domain["name"] as? String, "USDC")
        XCTAssertEqual(domain["version"] as? String, "2")
        XCTAssertEqual(domain["chainId"] as? Int, chainID)
        XCTAssertEqual(domain["verifyingContract"] as? String, usdc.value)

        let message = try XCTUnwrap(json["message"] as? [String: Any])
        // Amounts go over as decimal strings: a uint256 does not survive JSON's number
        // type, and 1.5 USDC quietly becoming a double would be a wrong cheque.
        XCTAssertEqual(message["value"] as? String, "1500000")
        XCTAssertEqual(message["validBefore"] as? String, "2000000000")
        XCTAssertEqual(message["nonce"] as? String, "0x" + String(repeating: "11", count: 32))
    }

    func testTheFieldOrderThatDefinesTheTypeIsNotAlphabetical() throws {
        let data = try ChequeAuthorization.typedData(for: goldenCheque, token: usdc, chainID: chainID)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let types = try XCTUnwrap(json["types"] as? [String: Any])
        let fields = try XCTUnwrap(types["TransferWithAuthorization"] as? [[String: String]])

        // EIP-712 hashes the type string built from this order, so sorting it would
        // change the digest. The struct is serialized with sortedKeys, which sorts the
        // keys of each entry and must never be allowed to sort the entries themselves.
        XCTAssertEqual(
            fields.map { $0["name"] },
            ["from", "to", "value", "validAfter", "validBefore", "nonce"]
        )
    }

    func testEveryNonceIsDifferentAndFullWidth() {
        let first = Cheque.randomNonce()
        let second = Cheque.randomNonce()
        // A guessable nonce is a cheque a stranger can cancel before it is cashed.
        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
    }

    func testChangingAnyFieldChangesTheDigest() {
        let base = ChequeAuthorization.digest(for: goldenCheque, token: usdc, chainID: chainID)
        var other = goldenCheque

        // Each of these is a different promise, so none may share a signature. The
        // recipient especially: it is what stops a leaked cheque paying anyone else.
        let variants: [Cheque] = [
            Cheque(from: other.from, to: other.from, amount: other.amount, validAfter: other.validAfter, validBefore: other.validBefore, nonce: other.nonce),
            Cheque(from: other.from, to: other.to, amount: USDCAmount(baseUnits: 1_500_001), validAfter: other.validAfter, validBefore: other.validBefore, nonce: other.nonce),
            Cheque(from: other.from, to: other.to, amount: other.amount, validAfter: 1, validBefore: other.validBefore, nonce: other.nonce),
            Cheque(from: other.from, to: other.to, amount: other.amount, validAfter: other.validAfter, validBefore: 1_999_999_999, nonce: other.nonce),
            Cheque(from: other.from, to: other.to, amount: other.amount, validAfter: other.validAfter, validBefore: other.validBefore, nonce: Data(repeating: 0x12, count: 32)),
        ]
        for variant in variants {
            XCTAssertNotEqual(ChequeAuthorization.digest(for: variant, token: usdc, chainID: chainID), base)
        }
        other = goldenCheque
        XCTAssertEqual(ChequeAuthorization.digest(for: other, token: usdc, chainID: chainID), base)
    }

    func testSignatureSplitNormalizesBothRecoveryIdConventions() throws {
        var signature = Data(repeating: 0xAB, count: 64)
        signature.append(0x00)
        // Libraries disagree about whether v is 0/1 or 27/28, and the token only
        // accepts the latter. Getting this wrong is a cheque that cannot be cashed.
        let (v, r, s) = try ArcContractWriter.split(signature: signature)
        XCTAssertEqual(v, 27)
        XCTAssertEqual(r.count, 32)
        XCTAssertEqual(s.count, 32)

        var already27 = Data(repeating: 0xAB, count: 64)
        already27.append(28)
        XCTAssertEqual(try ArcContractWriter.split(signature: already27).0, 28)
    }

    func testAMalformedSignatureIsRefusedRatherThanTruncated() {
        XCTAssertThrowsError(try ArcContractWriter.split(signature: Data(repeating: 0xAB, count: 64)))
    }

    func testADifferentChainCannotReuseTheSameSignature() {
        // The domain binds the chain, so a cheque written for Arc is not a cheque
        // anywhere else even though the token address may be identical.
        XCTAssertNotEqual(
            ChequeAuthorization.digest(for: goldenCheque, token: usdc, chainID: chainID),
            ChequeAuthorization.digest(for: goldenCheque, token: usdc, chainID: 1)
        )
    }
}
