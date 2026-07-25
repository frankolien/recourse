import XCTest
@testable import Recourse

final class SendWorkflowTests: XCTestCase {
    private let sender = EthereumAddress(trusted: "0x1000000000000000000000000000000000000001")
    private let recipient = EthereumAddress(trusted: "0x2000000000000000000000000000000000000002")

    func testSendsAfterBalanceCheckAndConfirmsReceipt() async throws {
        let gateway = FakeContractGateway(balance: USDCAmount(baseUnits: 5_000_000))

        let result = try await SendWorkflow(gateway: gateway).execute(
            recipient: recipient,
            amount: USDCAmount(baseUnits: 1_250_000),
            sender: sender
        )

        XCTAssertEqual(result.transactionHash, DomainFixture.transferHash)
        XCTAssertEqual(result.recipient, recipient)
        XCTAssertEqual(result.amount.baseUnits, 1_250_000)
        let calls = await gateway.recordedCalls()
        XCTAssertEqual(calls, [.transfer(recipient, USDCAmount(baseUnits: 1_250_000))])
    }

    func testRejectsZeroAmountBeforeAnyChainWork() async throws {
        let gateway = FakeContractGateway()

        do {
            _ = try await SendWorkflow(gateway: gateway).execute(
                recipient: recipient,
                amount: USDCAmount(baseUnits: 0),
                sender: sender
            )
            XCTFail("zero amount must be rejected")
        } catch let error as SendError {
            XCTAssertEqual(error, .zeroAmount)
        }
        let calls = await gateway.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testRejectsSendingToOwnAddress() async throws {
        let gateway = FakeContractGateway()

        do {
            _ = try await SendWorkflow(gateway: gateway).execute(
                recipient: sender,
                amount: USDCAmount(baseUnits: 1),
                sender: sender
            )
            XCTFail("self transfer must be rejected")
        } catch let error as SendError {
            XCTAssertEqual(error, .selfTransfer)
        }
        let calls = await gateway.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testRejectsInsufficientBalanceWithoutTransferring() async throws {
        let gateway = FakeContractGateway(balance: USDCAmount(baseUnits: 100))

        do {
            _ = try await SendWorkflow(gateway: gateway).execute(
                recipient: recipient,
                amount: USDCAmount(baseUnits: 200),
                sender: sender
            )
            XCTFail("insufficient balance must be rejected")
        } catch let error as SendError {
            XCTAssertEqual(error, .insufficientBalance(available: USDCAmount(baseUnits: 100)))
        }
        let calls = await gateway.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }
}
