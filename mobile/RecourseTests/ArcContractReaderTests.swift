import XCTest
@testable import Recourse

final class ArcContractReaderTests: XCTestCase {
    func testDecodesSeededArcReadFixtures() async throws {
        let transport = FixtureArcRPCTransport(responses: [
            Self.balanceCall: Self.balanceResponse,
            Self.allowanceCall: Self.allowanceResponse,
            Self.policyCall: Self.policyResponse,
            Self.policyHashCall: Self.policyHashResponse,
            Self.paymentCall: Self.paymentResponse,
            Self.verdictCall: Self.verdictResponse,
            Self.resolveDelayCall: Self.resolveDelayResponse
        ])
        let reader = try ArcContractReader(configuration: .live, transport: transport)
        let buyer = EthereumAddress(trusted: "0x15f1A215260994a4019497fa8267f2F6B479Bf6A")

        let balance = try await reader.usdcBalance(of: buyer)
        let allowance = try await reader.allowance(owner: buyer, spender: .init(trusted: Deployment.escrow))
        let policy = try await reader.policy(id: 1)
        let payment = try await reader.payment(id: 5)
        let verdict = try await reader.previewVerdict(paymentID: 5)
        let resolveDelay = try await reader.resolveDelay()

        XCTAssertEqual(balance.baseUnits, 1_190_481)
        XCTAssertEqual(allowance.baseUnits, 1_000_000)
        XCTAssertEqual(policy.id, 1)
        XCTAssertEqual(policy.merchant.value.lowercased(), "0xd70beb0ce6e261fdaa8cb72607316c6bca16a082")
        XCTAssertEqual(policy.disputeWindow, 1_209_600)
        XCTAssertEqual(policy.policyHash.value, "0xc5a2b6c0d2ca4aaeccbd262b6a47f414403914fdd6565b12da92768441fa892f")
        XCTAssertEqual(payment.id, 5)
        XCTAssertEqual(payment.amount.baseUnits, 250_000)
        XCTAssertEqual(payment.paidAt, 1_784_561_840)
        XCTAssertEqual(payment.filedAt, 1_784_561_857)
        XCTAssertEqual(payment.claimType, .notDelivered)
        XCTAssertEqual(payment.evidenceMask, 0)
        XCTAssertEqual(payment.attestationType, 1)
        XCTAssertEqual(payment.attestationValue, 2)
        XCTAssertEqual(payment.verdictBPS, 10_000)
        XCTAssertEqual(payment.status, .settled)
        XCTAssertEqual(verdict.refundBPS, 10_000)
        XCTAssertFalse(verdict.requiresReturn)
        XCTAssertEqual(verdict.ruleIndex, 0)
        XCTAssertTrue(verdict.matched)
        XCTAssertEqual(verdict.verdictHash.value, "0x683e3c325e6eeed6eecd3aa3fcbcf0d1c8a874e0acad2f0ba3809de0f7bc650f")
        XCTAssertEqual(resolveDelay, 60)
    }

    func testUsesReviewedFunctionSelectorsAndDeploymentAddresses() async throws {
        let transport = FixtureArcRPCTransport(responses: [
            Self.balanceCall: Self.balanceResponse,
            Self.resolveDelayCall: Self.resolveDelayResponse
        ])
        let reader = try ArcContractReader(configuration: .live, transport: transport)
        let buyer = EthereumAddress(trusted: "0x15f1A215260994a4019497fa8267f2F6B479Bf6A")

        _ = try await reader.usdcBalance(of: buyer)
        _ = try await reader.resolveDelay()

        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].address, .init(trusted: Deployment.usdc))
        XCTAssertEqual(calls[0].data, Self.balanceCall)
        XCTAssertEqual(calls[1].address, .init(trusted: Deployment.escrow))
        XCTAssertEqual(calls[1].data, Self.resolveDelayCall)
    }
}

private actor FixtureArcRPCTransport: ArcRPCTransport {
    struct Call: Sendable {
        let address: EthereumAddress
        let data: Data
    }

    private let responses: [Data: Data]
    private var calls: [Call] = []

    init(responses: [Data: Data]) {
        self.responses = responses
    }

    func call(to address: EthereumAddress, data: Data) async throws -> Data {
        calls.append(Call(address: address, data: data))
        guard let response = responses[data] else {
            throw ContractReadError.invalidRPCResponse
        }
        return response
    }

    func recordedCalls() -> [Call] { calls }
}

private extension ArcContractReaderTests {
    static let balanceCall = Data(hex: "70a0823100000000000000000000000015f1a215260994a4019497fa8267f2f6b479bf6a")
    static let allowanceCall = Data(hex: "dd62ed3e00000000000000000000000015f1a215260994a4019497fa8267f2f6b479bf6a00000000000000000000000061fd99789b28582882a3369e2024aeae5b5d2dc0")
    static let policyCall = Data(hex: "2b07fce30000000000000000000000000000000000000000000000000000000000000001")
    static let policyHashCall = Data(hex: "7b50c0f60000000000000000000000000000000000000000000000000000000000000001")
    static let paymentCall = Data(hex: "3280a8360000000000000000000000000000000000000000000000000000000000000005")
    static let verdictCall = Data(hex: "e4d76f860000000000000000000000000000000000000000000000000000000000000005")
    static let resolveDelayCall = Data(hex: "19b7c908")

    static let balanceResponse = Data(hex: "0000000000000000000000000000000000000000000000000000000000122a51")
    static let allowanceResponse = Data(hex: "00000000000000000000000000000000000000000000000000000000000f4240")
    static let policyResponse = Data(hex: "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000d70beb0ce6e261fdaa8cb72607316c6bca16a082000000000000000000000000000000000000000000000000000000000012750000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000127500000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003f48000000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000001")
    static let policyHashResponse = Data(hex: "c5a2b6c0d2ca4aaeccbd262b6a47f414403914fdd6565b12da92768441fa892f")
    static let paymentResponse = Data(hex: "00000000000000000000000015f1a215260994a4019497fa8267f2f6b479bf6a000000000000000000000000d70beb0ce6e261fdaa8cb72607316c6bca16a082000000000000000000000000d70beb0ce6e261fdaa8cb72607316c6bca16a0820000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000003d090000000000000000000000000000000000000000000000000000000000003d090000000000000000000000000000000000000000000000000000000006a5e40b0000000000000000000000000000000000000000000000000000000006a5e40c10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000003")
    static let verdictResponse = Data(hex: "0000000000000000000000000000000000000000000000000000000000002710000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001683e3c325e6eeed6eecd3aa3fcbcf0d1c8a874e0acad2f0ba3809de0f7bc650f")
    static let resolveDelayResponse = Data(hex: "000000000000000000000000000000000000000000000000000000000000003c")
}

extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start ..< end], radix: 16)!
        })
    }
}
