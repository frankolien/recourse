import XCTest
@testable import Recourse

final class BuyerSettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "buyer-settings-tests")
        defaults.removePersistentDomain(forName: "buyer-settings-tests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "buyer-settings-tests")
        super.tearDown()
    }

    // MARK: Payment limit

    func testZeroLimitMeansNoLimit() {
        XCTAssertFalse(PaymentLimit.exceeded(
            amount: USDCAmount(baseUnits: .max),
            limitBaseUnits: 0
        ))
    }

    func testAmountAtTheLimitIsAllowed() {
        XCTAssertFalse(PaymentLimit.exceeded(
            amount: USDCAmount(baseUnits: 250_000_000),
            limitBaseUnits: 250_000_000
        ))
    }

    func testAmountAboveTheLimitIsBlocked() {
        XCTAssertTrue(PaymentLimit.exceeded(
            amount: USDCAmount(baseUnits: 250_000_001),
            limitBaseUnits: 250_000_000
        ))
    }

    // MARK: Address book

    @MainActor
    func testAddressBookPersistsAcrossInstances() throws {
        let store = AddressBookStore(defaults: defaults)
        try store.add(label: "Ada", address: "0x1111111111111111111111111111111111111111")

        let reloaded = AddressBookStore(defaults: defaults)
        XCTAssertEqual(reloaded.recipients.count, 1)
        XCTAssertEqual(reloaded.recipients.first?.label, "Ada")
    }

    @MainActor
    func testAddressBookRejectsInvalidAddressAndDuplicates() throws {
        let store = AddressBookStore(defaults: defaults)
        XCTAssertThrowsError(try store.add(label: "Bad", address: "not-an-address")) { error in
            XCTAssertEqual(error as? AddressBookStore.AddError, .invalidAddress)
        }

        try store.add(label: "Ada", address: "0x1111111111111111111111111111111111111111")
        XCTAssertThrowsError(
            try store.add(label: "Twin", address: "0x1111111111111111111111111111111111111111")
        ) { error in
            XCTAssertEqual(error as? AddressBookStore.AddError, .duplicateAddress)
        }
    }

    @MainActor
    func testAddressBookRemovalPersists() throws {
        let store = AddressBookStore(defaults: defaults)
        try store.add(label: "Ada", address: "0x1111111111111111111111111111111111111111")
        store.remove(store.recipients[0])

        XCTAssertTrue(AddressBookStore(defaults: defaults).recipients.isEmpty)
    }

    // MARK: Biometric preference

    func testAuthorizerSkipsBiometricsWhenTurnedOff() async throws {
        // Local instance so the region can transfer into the actor; the shared
        // test property would trip strict-concurrency sending rules.
        let authorizerDefaults = UserDefaults(suiteName: "buyer-settings-authorizer")!
        authorizerDefaults.removePersistentDomain(forName: "buyer-settings-authorizer")
        authorizerDefaults.set(false, forKey: BuyerSettingKey.confirmPaymentsWithBiometrics)

        let authorizer = DeviceOwnerTransactionAuthorizer(defaults: authorizerDefaults)
        // With the preference off this must return without touching LocalAuthentication;
        // in the test environment an LAContext evaluation would throw .unavailable.
        try await authorizer.authorizeTransaction()
    }
}
