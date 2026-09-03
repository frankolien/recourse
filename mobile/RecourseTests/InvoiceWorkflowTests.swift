import XCTest
@testable import Recourse

/// The rules that decide whether an invoice can move money.
///
/// An invoice is a request for a cheque, so the signature is the whole mechanism. What
/// has to hold is that the terms cannot drift between what the issuer fixed and what
/// the payer signs, that a signature is only ever produced against a balance that can
/// honour it, and that neither side can act out of turn.
final class InvoiceWorkflowTests: XCTestCase {
    private let payer = DomainFixture.buyer
    private let issuer = EthereumAddress(trusted: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc")
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var now: Date { Self.now }

    private func workflow(
        gateway: FakeContractGateway = FakeContractGateway(),
        api: FakeInvoiceAPI = FakeInvoiceAPI()
    ) -> InvoiceWorkflow {
        InvoiceWorkflow(
            gateway: gateway,
            signer: InvoiceFixtureSigner(),
            api: api,
            configuration: .live,
            clock: { Self.now }
        )
    }

    // MARK: Issuing

    func testIssuingFixesTheTermsAndAsksForNothingOnChain() async throws {
        let api = FakeInvoiceAPI()
        let stored = try await workflow(api: api).issue(
            to: issuer,
            amount: USDCAmount(baseUnits: 5_000_000),
            terms: .fortnight,
            memo: "  design work  ",
            accessToken: "token"
        )

        let sent = await api.issued
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.amount, "5000000")
        XCTAssertEqual(sent.first?.memo, "design work")
        // The due date is the clock plus the chosen terms, so what the screen promised
        // is what the payer will be asked to sign over.
        XCTAssertEqual(
            sent.first?.validBefore,
            String(UInt64(now.timeIntervalSince1970) + InvoiceTerms.fortnight.seconds)
        )
        XCTAssertNil(stored.signature, "issuing must not produce an authorization")
    }

    func testAnInvoiceWithNoDescriptionIsRefused() async {
        do {
            _ = try await workflow().issue(
                to: issuer,
                amount: USDCAmount(baseUnits: 1_000_000),
                terms: .week,
                memo: "   ",
                accessToken: "token"
            )
            XCTFail("expected the invoice to be refused")
        } catch InvoiceError.missingMemo {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testYouCannotInvoiceYourself() async {
        do {
            _ = try await workflow().issue(
                to: payer,
                amount: USDCAmount(baseUnits: 1_000_000),
                terms: .week,
                memo: "rent",
                accessToken: "token"
            )
            XCTFail("expected a self invoice to be refused")
        } catch InvoiceError.selfInvoice {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: Paying

    func testPayingSignsTheAuthorizationTheInvoiceNames() async throws {
        let api = FakeInvoiceAPI()
        let invoice = self.invoice()
        let answered = try await workflow(
            gateway: FakeContractGateway(balance: USDCAmount(baseUnits: 20_000_000)),
            api: api
        ).pay(invoice, committed: USDCAmount(baseUnits: 0), accessToken: "token")

        XCTAssertNotNil(answered.signature)
        let signed = await api.signed
        XCTAssertEqual(signed.first?.0, invoice.invoiceId)
    }

    func testTheAuthorizationPaysTheIssuerFromThePayer() throws {
        // The direction is what makes an invoice a pull rather than a push. Getting it
        // backwards would sign over a transfer out of the wrong wallet.
        let authorization = try XCTUnwrap(invoice().authorization)
        XCTAssertEqual(authorization.from, payer)
        XCTAssertEqual(authorization.to, issuer)
        XCTAssertEqual(authorization.amount.baseUnits, 4_000_000)
    }

    func testPayingIsRefusedWhenChequesAlreadySpokeForTheBalance() async {
        // The same commitment arithmetic cheques use. Signing an invoice is another
        // promise against one balance, and two promises that overlap mean one bounces.
        let gateway = FakeContractGateway(balance: USDCAmount(baseUnits: 5_000_000))
        do {
            _ = try await workflow(gateway: gateway).pay(
                invoice(),
                committed: USDCAmount(baseUnits: 3_000_000),
                accessToken: "token"
            )
            XCTFail("expected the payment to be refused")
        } catch InvoiceError.overcommitted(let available) {
            XCTAssertEqual(available.baseUnits, 2_000_000)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAnInvoiceAddressedToSomeoneElseCannotBeSignedHere() async {
        let other = StoredInvoice(
            invoiceId: 9,
            issuer: issuer.value,
            payer: "0x3333333333333333333333333333333333333333",
            amount: "1000000",
            validAfter: "0",
            validBefore: "2000000000",
            nonce: "0x" + String(repeating: "c1", count: 32),
            memo: "not yours",
            signature: nil,
            signedAt: nil,
            cancelledAt: nil,
            createdAt: "2026-09-03T00:00:00Z"
        )
        do {
            _ = try await workflow().pay(other, committed: USDCAmount(baseUnits: 0), accessToken: "token")
            XCTFail("expected the payment to be refused")
        } catch InvoiceError.notYours {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAnInvoicePastItsDueDateCannotBeSigned() async {
        do {
            _ = try await workflow().pay(
                invoice(validBefore: UInt64(now.timeIntervalSince1970) - 1),
                committed: USDCAmount(baseUnits: 0),
                accessToken: "token"
            )
            XCTFail("expected the payment to be refused")
        } catch InvoiceError.expired {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAnInvoiceCannotBeSignedTwice() async {
        do {
            _ = try await workflow().pay(
                invoice(signature: "0x" + String(repeating: "ab", count: 65)),
                committed: USDCAmount(baseUnits: 0),
                accessToken: "token"
            )
            XCTFail("expected the payment to be refused")
        } catch InvoiceError.alreadyAnswered {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: Collecting

    func testCollectingSubmitsTheSignatureAndBurnsTheNonce() async throws {
        let gateway = FakeContractGateway()
        // The issuer collects, so the signer has to be the issuer for this one.
        let flow = InvoiceWorkflow(
            gateway: gateway,
            signer: InvoiceFixtureSigner(address: issuer),
            api: FakeInvoiceAPI(),
            configuration: .live,
            clock: { Self.now }
        )
        let signed = invoice(signature: "0x" + String(repeating: "ab", count: 65))
        _ = try await flow.collect(signed)

        let calls = await gateway.calls
        XCTAssertTrue(calls.contains(.cashCheque(signed.nonceBytes)))
    }

    func testAnUnsignedInvoiceHasNothingToCollect() async {
        let flow = InvoiceWorkflow(
            gateway: FakeContractGateway(),
            signer: InvoiceFixtureSigner(address: issuer),
            api: FakeInvoiceAPI(),
            configuration: .live,
            clock: { Self.now }
        )
        do {
            _ = try await flow.collect(invoice())
            XCTFail("expected collection to be refused")
        } catch InvoiceError.notSigned {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testThePayerCannotCollectTheirOwnInvoice() async {
        // Signed by the payer, so the signer here is the payer trying to submit an
        // invoice billed to them. Only the issuer is paid by it.
        do {
            _ = try await workflow().collect(invoice(signature: "0x" + String(repeating: "ab", count: 65)))
            XCTFail("expected collection to be refused")
        } catch InvoiceError.notYours {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: Withdrawing

    func testASignedInvoiceCannotBeWithdrawn() async {
        // Once a signature exists the authorization is live on chain, and a withdrawn
        // row would tell the payer they owe nothing while the issuer can still collect.
        do {
            _ = try await workflow().cancel(
                invoice(signature: "0x" + String(repeating: "ab", count: 65)),
                accessToken: "token"
            )
            XCTFail("expected the withdrawal to be refused")
        } catch InvoiceError.alreadyAnswered {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: Fixtures

    private func invoice(
        validBefore: UInt64 = 2_000_000_000,
        signature: String? = nil
    ) -> StoredInvoice {
        StoredInvoice(
            invoiceId: 1,
            issuer: issuer.value,
            payer: payer.value,
            amount: "4000000",
            validAfter: "0",
            validBefore: String(validBefore),
            nonce: "0x" + String(repeating: "b7", count: 32),
            memo: "design work",
            signature: signature,
            signedAt: signature == nil ? nil : "2026-09-03T00:00:00Z",
            cancelledAt: nil,
            createdAt: "2026-09-03T00:00:00Z"
        )
    }
}

private actor InvoiceFixtureSigner: BuyerSigner {
    private let wallet: EthereumAddress

    init(address: EthereumAddress = DomainFixture.buyer) {
        wallet = address
    }

    func address() async throws -> EthereumAddress { wallet }
    func sign(_ transaction: UnsignedTransaction) async throws -> Data { Data([0xaa]) }
    func signEIP712(_ typedData: Data) async throws -> Data { Data(repeating: 0x11, count: 65) }
    func reset() async throws {}
}

actor FakeInvoiceAPI: InvoiceAPI {
    private(set) var issued: [InvoiceDraft] = []
    private(set) var signed: [(Int64, Data)] = []
    private(set) var cancelled: [Int64] = []
    var inboxRows: [StoredInvoice] = []
    var outboxRows: [StoredInvoice] = []

    func issue(_ draft: InvoiceDraft, accessToken: String) async throws -> StoredInvoice {
        issued.append(draft)
        return StoredInvoice(
            invoiceId: Int64(issued.count),
            issuer: draft.issuer,
            payer: draft.payer,
            amount: draft.amount,
            validAfter: "0",
            validBefore: draft.validBefore,
            nonce: draft.nonce,
            memo: draft.memo,
            signature: nil,
            signedAt: nil,
            cancelledAt: nil,
            createdAt: "2026-09-03T00:00:00Z"
        )
    }

    func sign(invoiceID: Int64, signature: Data, accessToken: String) async throws -> StoredInvoice {
        signed.append((invoiceID, signature))
        return StoredInvoice(
            invoiceId: invoiceID,
            issuer: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc",
            payer: DomainFixture.buyer.value,
            amount: "4000000",
            validAfter: "0",
            validBefore: "2000000000",
            nonce: "0x" + String(repeating: "b7", count: 32),
            memo: "design work",
            signature: signature.hexString,
            signedAt: "2026-09-03T00:00:00Z",
            cancelledAt: nil,
            createdAt: "2026-09-03T00:00:00Z"
        )
    }

    func cancel(invoiceID: Int64, accessToken: String) async throws -> StoredInvoice {
        cancelled.append(invoiceID)
        return StoredInvoice(
            invoiceId: invoiceID,
            issuer: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc",
            payer: DomainFixture.buyer.value,
            amount: "4000000",
            validAfter: "0",
            validBefore: "2000000000",
            nonce: "0x" + String(repeating: "b7", count: 32),
            memo: "design work",
            signature: nil,
            signedAt: nil,
            cancelledAt: "2026-09-03T00:00:00Z",
            createdAt: "2026-09-03T00:00:00Z"
        )
    }

    func inbox(accessToken: String) async throws -> [StoredInvoice] { inboxRows }
    func outbox(accessToken: String) async throws -> [StoredInvoice] { outboxRows }
}
