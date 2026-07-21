import XCTest
@testable import Recourse

final class ArcContractWriterTests: XCTestCase {
    func testEncodesAndSubmitsEveryBuyerWrite() async throws {
        let signer = FixtureBuyerSigner()
        let transport = FixtureTransactionTransport()
        let writer = try ArcContractWriter(
            configuration: .live,
            signer: signer,
            transport: transport,
            pollClock: ImmediatePollClock()
        )
        let evidence = UploadedEvidence(
            kind: .photo,
            hash: ChainHash(trusted: "0x" + String(repeating: "cd", count: 32))
        )

        _ = try await writer.approveUSDC(amount: USDCAmount(baseUnits: 1_000_000))
        _ = try await writer.pay(DomainFixture.request)
        _ = try await writer.fileDispute(paymentID: 5, claimType: .notDelivered, evidence: [evidence])
        _ = try await writer.resolve(paymentID: 5)

        let calls = await transport.preparedCalls()
        let sentTransactions = await transport.sentTransactions()
        XCTAssertEqual(calls.map(\.to), [
            EthereumAddress(trusted: Deployment.usdc),
            EthereumAddress(trusted: Deployment.escrow),
            EthereumAddress(trusted: Deployment.escrow),
            EthereumAddress(trusted: Deployment.escrow)
        ])
        XCTAssertEqual(calls[0].data, Data(hex: "095ea7b300000000000000000000000061fd99789b28582882a3369e2024aeae5b5d2dc000000000000000000000000000000000000000000000000000000000000f4240"))
        XCTAssertEqual(calls[1].data, Data(hex: "c89a7cdf000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000017d7840abababababababababababababababababababababababababababababababab"))
        XCTAssertEqual(calls[2].data, Data(hex: "3f98cd5400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"))
        XCTAssertEqual(calls[3].data, Data(hex: "4f896d4f0000000000000000000000000000000000000000000000000000000000000005"))
        XCTAssertEqual(sentTransactions, Array(repeating: Data([0xaa, 0xbb]), count: 4))
    }

    func testReceiptReturnsPaymentIDFromPaidEvent() async throws {
        let transactionHash = ChainHash(trusted: "0x" + String(repeating: "12", count: 32))
        let paymentTopic = ChainHash(trusted: "0x" + String(repeating: "0", count: 63) + "9")
        let receipt = TransactionReceiptRecord(
            transactionHash: transactionHash,
            outcome: .confirmed,
            logs: [
                TransactionLogRecord(
                    address: EthereumAddress(trusted: Deployment.escrow),
                    topics: [
                        ChainHash(trusted: "0x49235e5c4cbb20ad7f9091e87b06dd12cddf489d77e8fd97a83cc5d4fc323e47"),
                        paymentTopic
                    ]
                )
            ]
        )
        let transport = FixtureTransactionTransport(receipts: [nil, receipt])
        let writer = try ArcContractWriter(
            configuration: .live,
            signer: FixtureBuyerSigner(),
            transport: transport,
            pollClock: ImmediatePollClock(),
            maximumReceiptPolls: 2
        )

        let result = try await writer.waitForReceipt(transactionHash: transactionHash)

        XCTAssertEqual(result.outcome, .confirmed)
        XCTAssertEqual(result.paymentID, 9)
    }

    func testReceiptPollingTimesOut() async throws {
        let writer = try ArcContractWriter(
            configuration: .live,
            signer: FixtureBuyerSigner(),
            transport: FixtureTransactionTransport(receipts: [nil, nil]),
            pollClock: ImmediatePollClock(),
            maximumReceiptPolls: 2
        )

        do {
            _ = try await writer.waitForReceipt(transactionHash: DomainFixture.paymentHash)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? ContractWriteError, .receiptTimedOut)
        }
    }
}

private actor FixtureBuyerSigner: BuyerSigner {
    func address() async throws -> EthereumAddress { DomainFixture.buyer }
    func sign(_ transaction: UnsignedTransaction) async throws -> Data { Data([0xaa, 0xbb]) }
    func reset() async throws {}
}

private actor FixtureTransactionTransport: ArcTransactionTransport {
    struct PreparedCall: Sendable {
        let from: EthereumAddress
        let to: EthereumAddress
        let data: Data
        let chainID: UInt64
    }

    private var calls: [PreparedCall] = []
    private var sent: [Data] = []
    private var receipts: [TransactionReceiptRecord?]

    init(receipts: [TransactionReceiptRecord?] = []) {
        self.receipts = receipts
    }

    func prepareTransaction(
        from: EthereumAddress,
        to: EthereumAddress,
        data: Data,
        chainID: UInt64
    ) async throws -> UnsignedTransaction {
        calls.append(PreparedCall(from: from, to: to, data: data, chainID: chainID))
        return UnsignedTransaction(
            chainID: chainID,
            from: from,
            to: to,
            nonce: UInt64(calls.count - 1),
            gasLimit: 200_000,
            gasPrice: 1,
            data: data
        )
    }

    func send(rawTransaction: Data) async throws -> ChainHash {
        sent.append(rawTransaction)
        return DomainFixture.paymentHash
    }

    func receipt(transactionHash: ChainHash) async throws -> TransactionReceiptRecord? {
        receipts.isEmpty ? nil : receipts.removeFirst()
    }

    func preparedCalls() -> [PreparedCall] { calls }
    func sentTransactions() -> [Data] { sent }
}

private struct ImmediatePollClock: TransactionPollClock {
    func sleep() async throws {}
}
