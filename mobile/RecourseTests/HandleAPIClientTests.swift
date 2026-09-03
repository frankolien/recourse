import XCTest
@testable import Recourse

final class HandleAPIClientTests: XCTestCase {
    func testStripsTheAtSignBeforeItReachesAURLPath() {
        // The server accepts a leading @ and so does the field, but putting one in a
        // URL path is an encoding bug waiting for a character that means nothing.
        XCTAssertEqual(HandleAPIClient.strip("@frank"), "frank")
        XCTAssertEqual(HandleAPIClient.strip("  @frank  "), "frank")
        XCTAssertEqual(HandleAPIClient.strip("frank"), "frank")
        XCTAssertEqual(HandleAPIClient.strip("@@frank"), "frank")
    }

    func testUnclaimedIsItsOwnCaseRatherThanAGenericFailure() {
        // The same 404 means "cannot send" when paying and "yours to take" when
        // choosing a name, so the caller has to be able to tell it apart.
        XCTAssertEqual(HandleAPIError.unclaimed.message, "No one is using that name.")
        XCTAssertNotEqual(
            HandleAPIError.unclaimed,
            HandleAPIError.rejected(status: 404, message: "no such handle")
        )
    }

    func testARefusalShowsTheServersOwnWordsRatherThanAStatusCode() {
        let error = HandleAPIError.rejected(status: 409, message: "that handle is taken")
        XCTAssertEqual(error.message, "that handle is taken")
    }
}
