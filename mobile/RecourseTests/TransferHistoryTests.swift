import XCTest
@testable import Recourse

/// History is only worth having if it names things right and the chart adds up.
final class TransferHistoryTests: XCTestCase {
    private let me = "0x1111111111111111111111111111111111111111"
    private let other = "0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc"
    private let usdc = "0x3600000000000000000000000000000000000000"
    private let vault = "0x5d8a3000866493f5d0b5b07a4ad63ade3b02054d"
    private let escrow = "0x61fd99789b28582882a3369e2024aeae5b5d2dc0"
    private let router = "0x4a5eba7b9d01fe0b9ccdab968b51b78cfa9a4c3b"

    private func context(payers: Set<String> = [], issuers: Set<String> = []) -> HistoryContext {
        HistoryContext(me: me, usdc: usdc, eurc: nil, vault: vault, escrow: escrow, fxRouter: router,
                       invoicePayers: payers, invoiceIssuers: issuers)
    }

    private func transfer(from: String, to: String, value: UInt64, method: String = "transfer", at seconds: TimeInterval = 1_700_000_000) -> TokenTransfer {
        TokenTransfer(hash: "0xabc", blockNumber: 1, timestamp: Date(timeIntervalSince1970: seconds),
                      from: from, to: to, value: value, token: usdc, symbol: "USDC", method: method)
    }

    // MARK: Naming

    func testAPlainTransferIsSentOrReceivedByDirection() {
        XCTAssertEqual(context().classify(transfer(from: me, to: other, value: 1))?.kind, .sent)
        XCTAssertEqual(context().classify(transfer(from: other, to: me, value: 1))?.kind, .received)
    }

    func testAnAuthorizationFromSomeoneYouBilledIsAnInvoiceBeingCollected() {
        // Same function on chain as a cheque; the only thing that tells them apart is
        // whether this account ever sent that person an invoice.
        let kind = context(payers: [other]).classify(transfer(from: other, to: me, value: 1, method: "transferWithAuthorization"))?.kind
        XCTAssertEqual(kind, .invoiceCollected)
        let cheque = context().classify(transfer(from: other, to: me, value: 1, method: "transferWithAuthorization"))?.kind
        XCTAssertEqual(cheque, .chequeYouCashed)
    }

    func testAnAuthorizationToSomeoneWhoBilledYouIsAnInvoicePaid() {
        let kind = context(issuers: [other]).classify(transfer(from: me, to: other, value: 1, method: "transferWithAuthorization"))?.kind
        XCTAssertEqual(kind, .invoicePaid)
        let cheque = context().classify(transfer(from: me, to: other, value: 1, method: "transferWithAuthorization"))?.kind
        XCTAssertEqual(cheque, .chequeCashed)
    }

    func testTheVaultAndTheRouterAreNamedByAddress() {
        XCTAssertEqual(context().classify(transfer(from: me, to: vault, value: 1))?.kind, .earnDeposit)
        XCTAssertEqual(context().classify(transfer(from: vault, to: me, value: 1))?.kind, .earnWithdrawal)
        XCTAssertEqual(context().classify(transfer(from: me, to: router, value: 1))?.kind, .converted)
        XCTAssertEqual(context().classify(transfer(from: escrow, to: me, value: 1))?.kind, .escrow)
    }

    func testTwoLegsOfOneTransactionAreAConversionWhateverSatInTheMiddle() {
        // What the explorer actually showed: USDC out to the pair and EURC back from it,
        // under one hash. Neither leg names the router, so the hash has to.
        let pair = "0xceff00000000000000000000000000000000ea8"
        let usdcLeg = TokenTransfer(hash: "0xswap", blockNumber: 1, timestamp: Date(), from: me, to: pair,
                                    value: 400_000, token: usdc, symbol: "USDC", method: "transfer")
        let eurcLeg = TokenTransfer(hash: "0xswap", blockNumber: 1, timestamp: Date(), from: pair, to: me,
                                    value: 339_855, token: "0xeurc", symbol: "EURC", method: "transfer")
        let entries = context().classify([usdcLeg, eurcLeg])
        XCTAssertEqual(entries.map(\.kind), [.converted, .converted])
        // A lone USDC transfer to the same address is still just a send.
        XCTAssertEqual(context().classify([usdcLeg]).map(\.kind), [.sent])
    }

    func testATransferThatDoesNotTouchThisWalletIsDropped() {
        XCTAssertNil(context().classify(transfer(from: other, to: vault, value: 1)))
    }

    // MARK: The chart

    func testTheBalanceIsWorkedBackwardsFromNow() {
        // Held 10 now. Received 4 an hour ago, sent 1 two hours ago. So three hours ago
        // the wallet held 10 - 4 + 1 = 7, and after the send but before the receipt, 6.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let transfers = [
            transfer(from: other, to: me, value: 4_000_000, at: now.timeIntervalSince1970 - 3600),
            transfer(from: me, to: other, value: 1_000_000, at: now.timeIntervalSince1970 - 7200),
        ]
        let samples = BalanceSeries.samples(current: 10_000_000, transfers: transfers, me: me, token: usdc,
                                            range: .day, now: now, count: 25)
        XCTAssertEqual(samples.count, 25)
        XCTAssertEqual(samples.first, 7_000_000, "before both movements")
        XCTAssertEqual(samples.last, 10_000_000, "now")
        // One hour per sample over a day of 25 samples, so sample 22 falls on the exact
        // second of the send and sample 23 on the exact second of the receipt. A
        // transfer stamped at the sample instant is in that block and has happened, so
        // 22 already reflects the send and 23 already reflects the receipt.
        XCTAssertEqual(samples[22], 6_000_000)
        XCTAssertEqual(samples[23], 10_000_000)
        XCTAssertEqual(samples[21], 7_000_000, "a second before the send, nothing has happened yet")
    }

    func testUndoingAReceiptNeverGoesBelowZero() {
        // Gas is paid in USDC and leaves no transfer, so the reconstruction can be off
        // by the fees spent. It must saturate rather than wrap.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let transfers = [transfer(from: other, to: me, value: 5_000_000, at: now.timeIntervalSince1970 - 60)]
        let samples = BalanceSeries.samples(current: 4_000_000, transfers: transfers, me: me, token: usdc,
                                            range: .day, now: now, count: 5)
        XCTAssertEqual(samples.first, 0)
    }

    func testOtherTokensDoNotMoveTheUSDCChart() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let eurc = TokenTransfer(hash: "0x1", blockNumber: 1, timestamp: now.addingTimeInterval(-60),
                                 from: other, to: me, value: 9_000_000, token: "0xeurc", symbol: "EURC", method: "transfer")
        let samples = BalanceSeries.samples(current: 1_000_000, transfers: [eurc], me: me, token: usdc,
                                            range: .day, now: now, count: 3)
        XCTAssertEqual(samples, [1_000_000, 1_000_000, 1_000_000])
    }

    // MARK: Decoding

    func testDecodesTheExplorersShape() throws {
        let json = """
        {"message":"OK","result":[{"value":"100000","blockNumber":"58283945","from":"0xFBEF7709e78ef704735f197b4b1ccab9a6ed9055","to":"0xd6c574461d96ee708f58fe553049ad4f48bb983a","contractAddress":"0x3600000000000000000000000000000000000000","tokenSymbol":"USDC","hash":"0x0B15","timeStamp":"1787392669","functionName":"resolve(uint256 id)"}]}
        """
        let rows = try ArcscanClient.decode(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].value, 100_000)
        XCTAssertEqual(rows[0].method, "resolve")
        XCTAssertEqual(rows[0].from, "0xfbef7709e78ef704735f197b4b1ccab9a6ed9055", "lowercased for comparison")
        XCTAssertEqual(rows[0].hash, "0x0b15")
        XCTAssertEqual(rows[0].timestamp, Date(timeIntervalSince1970: 1_787_392_669))
    }

    func testAnEmptyHistoryIsEmptyRatherThanAnError() throws {
        XCTAssertEqual(try ArcscanClient.decode(Data(#"{"message":"No transactions found","result":[]}"#.utf8)), [])
        XCTAssertEqual(try ArcscanClient.decode(Data(#"{"message":"No transactions found","result":"","status":"0"}"#.utf8)), [])
    }

    /// The bridge mint that arrived on 2026-09-11, copied from what the explorer
    /// actually answered. v2 is asked first because v1 was returning 429 that day.
    func testDecodesTheModernShape() throws {
        let json = """
        {"items":[{"block_number":61542916,"transaction_hash":"0x2F49E3516602","timestamp":"2026-09-11T09:15:29.000000Z",\
"from":{"hash":"0x0000000000000000000000000000000000000000"},"to":{"hash":"0xE97164D899245313b95bB7F44C35f5D17675bE70"},\
"total":{"value":"19900000","decimals":"6"},"token":{"address_hash":"0x3600000000000000000000000000000000000000","symbol":"USDC","decimals":"6"},\
"method":"0x57ecfd28","type":"token_minting"}],"next_page_params":null}
        """
        let rows = try ArcscanClient.decodeModern(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].value, 19_900_000)
        XCTAssertEqual(rows[0].token, "0x3600000000000000000000000000000000000000")
        XCTAssertEqual(rows[0].symbol, "USDC")
        XCTAssertEqual(rows[0].from, "0x0000000000000000000000000000000000000000", "a mint comes from nobody")
        XCTAssertEqual(rows[0].to, "0xe97164d899245313b95bb7f44c35f5d17675be70", "lowercased for comparison")
        XCTAssertEqual(rows[0].hash, "0x2f49e3516602")
        XCTAssertEqual(rows[0].blockNumber, 61_542_916)
        XCTAssertEqual(rows[0].method, "", "a bare selector is not a method name")
    }

    func testTheModernShapeNamesAMethodItKnows() throws {
        let json = """
        {"items":[{"block_number":1,"transaction_hash":"0xAA","timestamp":"2026-09-11T09:15:29.000000Z",\
"from":{"hash":"0x01"},"to":{"hash":"0x02"},"total":{"value":"5"},\
"token":{"address_hash":"0x03","symbol":"USDC"},"method":"transferWithAuthorization(address,address)"}]}
        """
        XCTAssertEqual(try ArcscanClient.decodeModern(Data(json.utf8))[0].method, "transferWithAuthorization")
    }
}
