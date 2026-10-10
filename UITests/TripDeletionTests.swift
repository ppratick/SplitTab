import XCTest

final class TripDeletionTests: XCTestCase {
    @MainActor func testCancelThenDeleteTripAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.buttons["home.trips"].tap(); app.buttons["Create Trip"].tap()
        let name = "Delete test " + String(UUID().uuidString.prefix(6))
        app.textFields["Trip name"].tap(); app.textFields["Trip name"].typeText(name)
        let person = app.textFields.matching(identifier: "Name").element(boundBy: 1)
        person.tap(); person.typeText("Alex")
        app.buttons["Create"].tap()
        for _ in 0..<30 {
            if app.collectionViews.staticTexts[name].exists { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        app.collectionViews.staticTexts[name].tap()
        for _ in 0..<5 {
            if app.buttons["Delete Trip"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["Delete Trip"].tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Delete Trip"].exists)
        app.buttons["Delete Trip"].tap()
        app.alerts.buttons["Delete Trip"].tap()
        XCTAssertTrue(app.navigationBars["Trips"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.collectionViews.staticTexts[name].exists)
        app.terminate(); app.launch()
        app.buttons["home.trips"].tap()
        XCTAssertFalse(app.collectionViews.staticTexts[name].exists)
    }
}
