import XCTest

final class ReceiptInteractionTests: XCTestCase {
    @MainActor func testKeyboardDismissAndSwipeDelete() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.buttons["home.bill"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Home"].exists)
        app.buttons["Manual Entry"].tap()
        app.buttons["Add Item"].tap()
        app.textFields["Item name"].tap(); app.textFields["Item name"].typeText("Taxi")
        app.textFields["0.00"].tap(); app.textFields["0.00"].typeText("1,250.50")
        XCTAssertTrue(app.buttons["keyboard.dismiss"].waitForExistence(timeout: 5))
        app.buttons["keyboard.dismiss"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["Add"].tap()
        let name = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "receipt.name.")).firstMatch
        XCTAssertEqual(name.value as? String, "Taxi")
        let row = app.cells.containing(.textField, identifier: name.identifier).firstMatch
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Receipt swipe deletion"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Delete"].tap()
        XCTAssertFalse(name.exists)
        XCTAssertFalse(app.navigationBars.buttons["Continue"].isEnabled)
    }
}
