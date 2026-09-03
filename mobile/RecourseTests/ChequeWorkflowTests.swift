import XCTest
@testable import Recourse

/// The rules that keep a cheque from being a promise nobody can keep.
///
/// EIP-3009 reserves nothing, so every guard here is the app's own. A test suite that
/// only proved the digest was right would miss the failure that actually costs someone
/// money: writing more cheques than the balance covers, and finding out when the last
/// person to arrive is turned away.
final class ChequeWorkflowTests: XCTestCase {
    private let recipient = EthereumAddress(trusted: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc")

    private func workflow(
        gateway: FakeContractGateway,
        api: FakeChequeAPI = FakeChequeAPI()
    ) -> ChequeWorkflow {
        ChequeWorkflow(
            gateway: gateway,
            signer: ChequeFixtureSigner(),
            api: api,
            configuration: .live,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func testWritingSignsTheChequeAndHandsItToThePostbox() async throws {
        let api = FakeChequeAPI()
        let stored = try await workflow(
            gateway: FakeContractGateway(balance: USDCAmount(baseUnits: 20_000_000)),
            api: api
        ).write(
            to: recipient,
            amount: USDCAmount(baseUnits: 5_000_000),
            validity: .week,
            memo: "  rent  ",
            committed: USDCAmount(baseUnits: 0),
            accessToken: "token"
        )

        XCTAssertEqual(stored.amount, "5000000")
        let sent = await api.written
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.to, recipient.value)
        // Trimmed, because a memo of spaces is not a memo.
        XCTAssertEqual(sent.first?.memo, "rent")
        // validBefore is the clock plus the chosen window, so the cheque expires when
        // the screen said it would.
        XCTAssertEqual(sent.first?.validBefore, String(1_700_000_000 + ChequeValidity.week.seconds))
        // Zero rather than now: the token requires validAfter strictly in the past, and
        // a fast device clock would otherwise write a cheque nobody can cash yet.
        XCTAssertEqual(sent.first?.validAfter, "0")
    }

    func testAChequeIsRefusedWhenEarlierChequesAlreadySpokeForTheBalance() async {
        // The bounce this whole feature has to avoid: 15 held, 10 already promised,
        // and someone about to promise 10 more.
        let gateway = FakeContractGateway(balance: USDCAmount(baseUnits: 15_000_000))
        do {
            _ = try await workflow(gateway: gateway).write(
                to: recipient,
                amount: USDCAmount(baseUnits: 10_000_000),
                validity: .week,
                memo: nil,
                committed: USDCAmount(baseUnits: 10_000_000),
                accessToken: "token"
            )
            XCTFail("expected the cheque to be refused")
        } catch ChequeError.overcommitted(let available) {
            XCTAssertEqual(available.baseUnits, 5_000_000)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAChequeForExactlyWhatIsLeftIsAllowed() async throws {
        let gateway = FakeContractGateway(balance: USDCAmount(baseUnits: 15_000_000))
        let stored = try await workflow(gateway: gateway).write(
            to: recipient,
            amount: USDCAmount(baseUnits: 5_000_000),
            validity: .day,
            memo: nil,
            committed: USDCAmount(baseUnits: 10_000_000),
            accessToken: "token"
        )
        XCTAssertEqual(stored.amount, "5000000")
    }

    func testAChequeToYourselfIsRefused() async {
        let gateway = FakeContractGateway(balance: USDCAmount(baseUnits: 20_000_000))
        do {
            _ = try await workflow(gateway: gateway).write(
                to: DomainFixture.buyer,
                amount: USDCAmount(baseUnits: 1_000_000),
                validity: .week,
                memo: nil,
                committed: USDCAmount(baseUnits: 0),
                accessToken: "token"
            )
            XCTFail("expected a self cheque to be refused")
        } catch ChequeError.selfCheque {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCashingSubmitsTheStoredSignatureAndBurnsTheNonce() async throws {
        let gateway = FakeContractGateway()
        let stored = storedCheque(to: DomainFixture.buyer)
        _ = try await workflow(gateway: gateway).cash(stored)

        let calls = await gateway.calls
        XCTAssertTrue(calls.contains(.cashCheque(stored.nonceBytes)))
        // The token now refuses it, which is what stops a second tap costing gas.
        let spent = try await gateway.authorizationState(
            authorizer: EthereumAddress(trusted: stored.from),
            nonce: stored.nonceBytes
        )
        XCTAssertTrue(spent)
    }

    func testCashingAChequeAlreadySpentIsRefusedBeforeAnyGasIsPaid() async {
        let gateway = FakeContractGateway()
        let stored = storedCheque(to: DomainFixture.buyer)
        await gateway.markSpent(authorizer: EthereumAddress(trusted: stored.from), nonce: stored.nonceBytes)

        do {
            _ = try await workflow(gateway: gateway).cash(stored)
            XCTFail("expected the cheque to be refused")
        } catch ChequeError.alreadySettled {
            let calls = await gateway.calls
            XCTAssertFalse(calls.contains { if case .cashCheque = $0 { true } else { false } })
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAChequeWrittenToSomeoneElseCannotBeCashedHere() async {
        // Not a security boundary, the token is that. It stops someone paying gas to
        // watch the chain refuse them.
        let stored = storedCheque(to: EthereumAddress(trusted: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"))
        do {
            _ = try await workflow(gateway: FakeContractGateway()).cash(stored)
            XCTFail("expected the cheque to be refused")
        } catch ChequeError.notYours {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAnExpiredChequeIsNotSubmitted() async {
        let stored = storedCheque(to: DomainFixture.buyer, validBefore: 1_699_999_999)
        do {
            _ = try await workflow(gateway: FakeContractGateway()).cash(stored)
            XCTFail("expected the cheque to be refused")
        } catch ChequeError.expiryInThePast {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testOnlyTheWriterCanVoid() async {
        let stored = storedCheque(from: recipient, to: DomainFixture.buyer)
        do {
            _ = try await workflow(gateway: FakeContractGateway()).void(stored)
            XCTFail("expected voiding to be refused")
        } catch ChequeError.notYours {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testVoidingBurnsTheNonceOfTheChequeItNames() async throws {
        let gateway = FakeContractGateway()
        let stored = storedCheque(from: DomainFixture.buyer, to: recipient)
        _ = try await workflow(gateway: gateway).void(stored)

        let calls = await gateway.calls
        XCTAssertTrue(calls.contains(.voidCheque(stored.nonceBytes)))
    }

    // MARK: Fixtures

    private func storedCheque(
        from: EthereumAddress = EthereumAddress(trusted: "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A"),
        to: EthereumAddress,
        validBefore: UInt64 = 2_000_000_000
    ) -> StoredCheque {
        StoredCheque(
            chequeId: 1,
            from: from.value,
            to: to.value,
            amount: "2500000",
            validAfter: "0",
            validBefore: String(validBefore),
            nonce: "0x" + String(repeating: "a1", count: 32),
            signature: "0x" + String(repeating: "bb", count: 65),
            memo: nil,
            createdAt: "2026-09-03T00:00:00Z"
        )
    }
}

private actor ChequeFixtureSigner: BuyerSigner {
    func address() async throws -> EthereumAddress { DomainFixture.buyer }
    func sign(_ transaction: UnsignedTransaction) async throws -> Data { Data([0xaa]) }
    func signEIP712(_ typedData: Data) async throws -> Data { Data(repeating: 0x11, count: 65) }
    func reset() async throws {}
}

actor FakeChequeAPI: ChequeAPI {
    private(set) var written: [ChequeDraft] = []
    var inboxRows: [StoredCheque] = []
    var outboxRows: [StoredCheque] = []

    func write(_ draft: ChequeDraft, accessToken: String) async throws -> StoredCheque {
        written.append(draft)
        return StoredCheque(
            chequeId: Int64(written.count),
            from: draft.from,
            to: draft.to,
            amount: draft.amount,
            validAfter: draft.validAfter,
            validBefore: draft.validBefore,
            nonce: draft.nonce,
            signature: draft.signature,
            memo: draft.memo,
            createdAt: "2026-09-03T00:00:00Z"
        )
    }

    func inbox(accessToken: String) async throws -> [StoredCheque] { inboxRows }
    func outbox(accessToken: String) async throws -> [StoredCheque] { outboxRows }
}
