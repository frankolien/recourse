import AuthenticationServices
import XCTest
@testable import Recourse

@MainActor
final class AccountSessionTests: XCTestCase {
    func testRestoresAnAuthorizedBackendSession() async throws {
        let secureStore = AccountSessionMemoryStore()
        let sessionStore = AccountSessionStore(secureStore: secureStore)
        let expected = account()
        let storedGrant = grant(account: expected)
        try await sessionStore.save(storedGrant)
        let api = AccountAPIMock(profile: expected, refreshedGrant: storedGrant)
        let session = AccountSession(
            store: sessionStore,
            credentialChecker: FixedAppleCredentialChecker(state: .authorized),
            api: api
        )

        await session.restore()

        XCTAssertEqual(session.account, expected)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertFalse(session.isRestoring)
    }

    func testExpiredAccessTokenUsesRotatingRefreshToken() async throws {
        let secureStore = AccountSessionMemoryStore()
        let sessionStore = AccountSessionStore(secureStore: secureStore)
        let expected = account()
        let refreshedGrant = grant(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            account: expected
        )
        try await sessionStore.save(grant(account: expected))
        let api = AccountAPIMock(
            profile: nil,
            refreshedGrant: refreshedGrant,
            meError: .rejected(status: 401, message: "expired")
        )
        let session = AccountSession(
            store: sessionStore,
            credentialChecker: FixedAppleCredentialChecker(state: .authorized),
            api: api
        )

        await session.restore()

        XCTAssertEqual(session.account, expected)
        let saved = try await sessionStore.load()
        XCTAssertEqual(saved, refreshedGrant)
    }

    func testRevokedAppleAccountIsRemovedFromKeychain() async throws {
        let secureStore = AccountSessionMemoryStore()
        let sessionStore = AccountSessionStore(secureStore: secureStore)
        try await sessionStore.save(grant(account: account()))
        let session = AccountSession(
            store: sessionStore,
            credentialChecker: FixedAppleCredentialChecker(state: .revoked),
            api: AccountAPIMock(profile: account(), refreshedGrant: grant(account: account()))
        )

        await session.restore()

        XCTAssertNil(session.account)
        let storedGrant = try await sessionStore.load()
        XCTAssertNil(storedGrant)
    }

    func testAccountLabelPrefersEmailThenName() {
        let emailAccount = AuthenticatedAccount(
            accountID: 1,
            providerUserID: "email-user",
            email: "buyer@example.com",
            givenName: "Buyer",
            familyName: "One"
        )
        let nameAccount = AuthenticatedAccount(
            accountID: 2,
            providerUserID: "name-user",
            email: nil,
            givenName: "Frank",
            familyName: "Olien"
        )

        XCTAssertEqual(emailAccount.accountLabel, "buyer@example.com")
        XCTAssertEqual(nameAccount.accountLabel, "Frank Olien")
    }

    private func account() -> AuthenticatedAccount {
        AuthenticatedAccount(
            accountID: 11,
            providerUserID: "apple-user-123",
            email: "frank@example.com",
            givenName: "Frank",
            familyName: "Olien"
        )
    }

    private func grant(
        accessToken: String = "access",
        refreshToken: String = "refresh",
        account: AuthenticatedAccount
    ) -> AccountSessionGrant {
        AccountSessionGrant(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiresAt: 4_000_000_000,
            refreshExpiresAt: 4_100_000_000,
            account: account
        )
    }
}

final class WorkspaceRoutingTests: XCTestCase {
    func testRestoringAlwaysShowsTheRestorationBoundary() {
        let destination = WorkspaceRouting.destination(
            isRestoring: true,
            isAuthenticated: true,
            hasCompletedOnboarding: true,
            storedRole: OnboardingRole.buyer.rawValue
        )

        XCTAssertEqual(destination, .restoring)
    }

    func testBuyerRoleRoutesToTheNativeBuyerApp() {
        let destination = WorkspaceRouting.destination(
            isRestoring: false,
            isAuthenticated: true,
            hasCompletedOnboarding: true,
            storedRole: OnboardingRole.buyer.rawValue
        )

        XCTAssertEqual(destination, .buyerApp)
    }

    func testMerchantRoleRoutesToTheWebHandoff() {
        let destination = WorkspaceRouting.destination(
            isRestoring: false,
            isAuthenticated: true,
            hasCompletedOnboarding: true,
            storedRole: OnboardingRole.merchant.rawValue
        )

        XCTAssertEqual(destination, .merchantWeb)
    }

    func testMissingOrInvalidRoleReturnsToOnboarding() {
        XCTAssertEqual(
            WorkspaceRouting.destination(
                isRestoring: false,
                isAuthenticated: true,
                hasCompletedOnboarding: true,
                storedRole: ""
            ),
            .onboarding
        )
        XCTAssertEqual(
            WorkspaceRouting.destination(
                isRestoring: false,
                isAuthenticated: false,
                hasCompletedOnboarding: true,
                storedRole: OnboardingRole.buyer.rawValue
            ),
            .onboarding
        )
    }
}

private actor AccountSessionMemoryStore: SecureDataStore {
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        values[account] = data
    }

    func load(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}

private actor AccountAPIMock: AccountAPI {
    let profile: AuthenticatedAccount?
    let refreshedGrant: AccountSessionGrant
    let meError: AccountAPIError?

    init(
        profile: AuthenticatedAccount?,
        refreshedGrant: AccountSessionGrant,
        meError: AccountAPIError? = nil
    ) {
        self.profile = profile
        self.refreshedGrant = refreshedGrant
        self.meError = meError
    }

    func appleChallenge() async throws -> AppleAuthChallenge {
        AppleAuthChallenge(nonce: "nonce", expiresAt: 4_000_000_000, ttlSecs: 300)
    }

    func exchangeAppleCode(
        authorizationCode: String,
        nonce: String,
        givenName: String?,
        familyName: String?
    ) async throws -> AccountSessionGrant {
        refreshedGrant
    }

    func refresh(refreshToken: String) async throws -> AccountSessionGrant {
        refreshedGrant
    }

    func me(accessToken: String) async throws -> AuthenticatedAccount {
        if let meError { throw meError }
        guard let profile else { throw AccountAPIError.invalidResponse }
        return profile
    }

    func logout(accessToken: String) async throws {}
}

@MainActor
private struct FixedAppleCredentialChecker: AppleCredentialStateChecking {
    let state: ASAuthorizationAppleIDProvider.CredentialState

    func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        state
    }
}
