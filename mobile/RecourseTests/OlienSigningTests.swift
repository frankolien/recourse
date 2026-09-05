import XCTest
@testable import Recourse

/// What the phone must get byte for byte right to act as a member: the id the
/// Olien knows the Safe by, the calldata a veto sends, and the hash a signature
/// covers. The reference hash came from viem 2.55.4's `hashTypedData` over the
/// same typed data, so the parser here and the wallet a hardware signer uses agree.
final class OlienSigningTests: XCTestCase {
    private let safe = EthereumAddress(trusted: "0x93B5497A85be58436E6667140C9AaC7Fac9E5304")

    func testASignerIdIsTheAddressLeftPaddedToAWordInLowercase() {
        let id = OlienSigning.signerID(for: safe)
        XCTAssertEqual(id, OlienFixture.safeSignerID)
        XCTAssertEqual(id.count, 66)
        XCTAssertTrue(id.hasPrefix("0x" + String(repeating: "0", count: 24)))
        XCTAssertEqual(id, id.lowercased(), "the service compares ids as lowercase hex")
    }

    func testTheVetoSelectorIsTheFirstFourBytesOfKeccakOfTheSignature() {
        XCTAssertEqual(OlienSigning.vetoSelector, SafeHashing.keccak("veto(bytes32)").prefix(4))
        XCTAssertEqual(OlienSigning.vetoSelector.hexString, "0xfb6f93f9")
    }

    func testVetoCalldataIsTheSelectorFollowedByTheHash() throws {
        let hash = try ChainHash(OlienFixture.txHash)
        let data = OlienSigning.vetoCalldata(hash: hash)
        XCTAssertEqual(data.count, 36)
        XCTAssertEqual(data.prefix(4).hexString, "0xfb6f93f9")
        XCTAssertEqual(data.suffix(32).hexString, OlienFixture.txHash)
        // The same bytes the service describes in its veto-call answer.
        let call = try OlienFixture.decode(VetoCall.self, OlienFixture.vetoCall)
        XCTAssertEqual(call.data, data.hexString)
    }

    func testTheFixturesTypedDataHashesToItsTxHash() throws {
        let proposal = try OlienFixture.decode(OlienProposal.self, OlienFixture.proposal)
        let hash = try OlienSigning.transactionHash(typedData: proposal.typedDataJSON())
        XCTAssertEqual(hash.value, OlienFixture.txHash)
    }

    func testAChangedFieldChangesTheHash() throws {
        // The whole point of recomputing: a service that sent one hash and data for
        // another is caught before the Safe signs anything.
        let json = OlienFixture.proposal.replacingOccurrences(of: "\"validUntil\": 1789200000 }", with: "\"validUntil\": 1789200001 }")
        let proposal = try OlienFixture.decode(OlienProposal.self, json)
        let hash = try OlienSigning.transactionHash(typedData: proposal.typedDataJSON())
        XCTAssertNotEqual(hash.value, OlienFixture.txHash)
    }

    func testTypedDataThatIsNotTypedDataIsRefusedRatherThanHashed() {
        XCTAssertThrowsError(try OlienSigning.transactionHash(typedData: Data("{}".utf8)))
    }
}
