import BigInt
import XCTest
@testable import Recourse

/// Every expected value here came from Arc testnet on 2026-09-03: the Safe at
/// 0x93B5497A85be58436E6667140C9AaC7Fac9E5304 answered `getMessageHash`, and the
/// operation hash was recomputed with cast and confirmed by a user operation the
/// bundler accepted. If a formula drifts, a signature the Safe rejects is the failure.
final class SafeSigningTests: XCTestCase {
    private let chainID: UInt64 = 5_042_002
    private let safe = EthereumAddress(trusted: "0x93B5497A85be58436E6667140C9AaC7Fac9E5304")
    private let module = EthereumAddress(trusted: "0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226")
    private let entryPoint = EthereumAddress(trusted: "0x0000000071727De22E5E9d8BAf0edAc6f37da032")
    private let usdc = EthereumAddress(trusted: "0x3600000000000000000000000000000000000000")
    private let cloud = EthereumAddress(trusted: "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A")

    func testTypeHashesMatchTheSafeContracts() {
        XCTAssertEqual(
            SafeHashing.messageTypeHash.hexString,
            "0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca"
        )
        XCTAssertEqual(
            SafeHashing.domainSeparator(chainID: chainID, verifyingContract: safe).hexString,
            "0x1731f9c53302ab5b7ba227aedc7fcb6cc838c09d93f02da41f2524bb618b0666"
        )
        XCTAssertEqual(
            SafeHashing.domainSeparator(chainID: chainID, verifyingContract: module).hexString,
            "0x6e8881d9796b240a9b34e1097e13cfecbfb7f34eaf701e790f521eab20d132c0"
        )
    }

    func testMessageHashMatchesGetMessageHash() throws {
        let digest = try XCTUnwrap(Data(hexString: "0x08b814247d6cba55bf8a1f4b5a9efd045550924bae95358b6d6bad8ee29b333b"))
        XCTAssertEqual(
            SafeHashing.messageHash(safe: safe, chainID: chainID, digest: digest).hexString,
            "0xc2c87f8d682fcdbaff97ea3777ff9a46b9b5b06d5eaec779e49c0552fe1bb848"
        )
    }

    func testExecuteUserOpCalldataMatchesCast() throws {
        let transfer = try XCTUnwrap(Data(hexString:
            "0xa9059cbb000000000000000000000000d6c574461d96ee708f58fe553049ad4f48bb983a0000000000000000000000000000000000000000000000000000000000001388"
        ))
        let callData = SafeCalldata.executeUserOp(to: usdc, data: transfer)
        XCTAssertEqual(
            callData.hexString,
            "0x7bb3742800000000000000000000000036000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000d6c574461d96ee708f58fe553049ad4f48bb983a000000000000000000000000000000000000000000000000000000000000138800000000000000000000000000000000000000000000000000000000"
        )
    }

    func testOperationHashMatchesTheModuleDomain() throws {
        let transfer = try XCTUnwrap(Data(hexString:
            "0xa9059cbb000000000000000000000000d6c574461d96ee708f58fe553049ad4f48bb983a0000000000000000000000000000000000000000000000000000000000001388"
        ))
        let hash = SafeHashing.operationHash(
            module: module,
            chainID: chainID,
            safe: safe,
            nonce: 7,
            callData: SafeCalldata.executeUserOp(to: usdc, data: transfer),
            verificationGasLimit: 140_687,
            callGasLimit: 50_180,
            preVerificationGas: 51_620,
            maxPriorityFeePerGas: 5_500_000_000,
            maxFeePerGas: 31_900_000_000,
            entryPoint: entryPoint
        )
        XCTAssertEqual(hash.hexString, "0x8ec5d0e333d3362fea773e4ae80348f4273f0366f509de65d1a551b71451580a")
    }

    func testSwapOwnerCalldataUsesTheSafeSelector() {
        let data = SafeCalldata.swapOwner(previous: .safeSentinel, old: cloud, new: usdc)
        XCTAssertEqual(data.count, 4 + 3 * 32)
        XCTAssertEqual(data.prefix(4).hexString, "0xe318b52b")
        XCTAssertEqual(data.suffix(20).hexString.lowercased(), usdc.value.lowercased())
    }

    func testSignaturesPackInOwnerOrderWithContractBytesInTheTail() throws {
        let device = EthereumAddress(trusted: "0x35B0711c955CC7B3C1bdf2eDC35e98EfF8872027")
        let ecdsa = Data(repeating: 0xaa, count: 64) + Data([0x1b])
        let p256 = Data(repeating: 0xcc, count: 64)
        let packed = try SafeSignatures.pack([
            .ecdsa(owner: cloud, signature: ecdsa),
            .contract(owner: device, signature: p256),
        ])

        // 0x35B0... sorts before 0xD6c5..., so the contract owner's static part leads.
        XCTAssertEqual(packed.count, 130 + 32 + 64)
        XCTAssertEqual(packed[12 ..< 32].hexString.lowercased(), device.value.lowercased())
        XCTAssertEqual(BigUInt(packed[32 ..< 64]), 130, "s points just past both static parts")
        XCTAssertEqual(packed[64], 0, "v = 0 marks a contract signature")
        XCTAssertEqual(packed[65 ..< 130], ecdsa)
        XCTAssertEqual(BigUInt(packed[130 ..< 162]), 64)
        XCTAssertEqual(packed[162 ..< 226], p256)
    }

    func testRecoveryIDBelowTwentySevenIsLifted() throws {
        let raw = Data(repeating: 0x11, count: 64) + Data([0x01])
        let packed = try SafeSignatures.pack([.ecdsa(owner: cloud, signature: raw)])
        XCTAssertEqual(packed[64], 28)
    }

    func testAnECDSASignatureMustBeSixtyFiveBytes() {
        XCTAssertThrowsError(try SafeSignatures.pack([.ecdsa(owner: cloud, signature: Data(repeating: 1, count: 64))])) { error in
            XCTAssertEqual(error as? SafeSignatureError, .malformedECDSA(count: 64))
        }
    }

    func testTransactionHashIsDeterministic() {
        let data = SafeCalldata.swapOwner(previous: .safeSentinel, old: cloud, new: usdc)
        let first = SafeHashing.transactionHash(safe: safe, chainID: chainID, to: safe, data: data, nonce: 3)
        let second = SafeHashing.transactionHash(safe: safe, chainID: chainID, to: safe, data: data, nonce: 4)
        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
    }
}
