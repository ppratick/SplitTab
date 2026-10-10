import XCTest

final class ResultsCopyTests: XCTestCase {
    @MainActor func testFourCopyActions() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.buttons["home.bill"].tap()
        app.buttons["Manual Entry"].tap()
        app.buttons["Add Item"].tap()
        app.textFields["Item name"].tap(); app.textFields["Item name"].typeText("Dinner")
        app.textFields["0.00"].tap(); app.textFields["0.00"].typeText("20")
        app.buttons["Add"].tap()
        let nameField = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "receipt.name.")).firstMatch
        nameField.tap(); nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        XCTAssertFalse(app.navigationBars.buttons["Continue"].isEnabled)
        nameField.typeText("Lunch")
        let priceField = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "receipt.price.")).firstMatch
        priceField.doubleTap(); priceField.typeText("30")
        XCTAssertEqual(priceField.value as? String, "30")
        XCTAssertTrue(app.navigationBars.buttons["Continue"].isEnabled)
        app.navigationBars.buttons["Continue"].tap()
        app.buttons["split.even"].tap()
        let names = app.textFields.matching(identifier: "Name")
        names.element(boundBy: 0).tap(); names.element(boundBy: 0).typeText("Alex")
        names.element(boundBy: 1).tap(); names.element(boundBy: 1).typeText("Sam")
        app.swipeUp()
        app.buttons["Calculate"].tap()
        XCTAssertTrue(app.buttons["copy.all.totals"].waitForExistence(timeout: 5))
        app.buttons["copy.all.totals"].tap()
        XCTAssertTrue(app.staticTexts["Everyone’s totals copied"].exists)
        app.buttons["copy.all.breakdown"].tap()
        XCTAssertTrue(app.staticTexts["Everyone’s breakdown copied"].exists)
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "copy.person.total.")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "copy.person.breakdown.")).firstMatch.tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Four copy actions"; shot.lifetime = .keepAlways; add(shot)
    }
}
