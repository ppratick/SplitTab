import XCTest

final class CurrencyFlowTests: XCTestCase {
    @MainActor func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor func testHomeAndMixedCurrencyExpense() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.bill"].waitForExistence(timeout: 15))
        shot(app, "Opening home")
        app.buttons["home.trips"].tap()
        app.buttons["Create Trip"].tap()
        let name = "Curaçao " + String(UUID().uuidString.prefix(5))
        app.textFields["Trip name"].tap(); app.textFields["Trip name"].typeText(name)
        let person = app.textFields.matching(identifier: "Name").element(boundBy: 1)
        person.tap(); person.typeText("Alex")
        app.buttons["Create"].tap()
        for _ in 0..<20 {
            if app.collectionViews.staticTexts[name].exists { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        app.collectionViews.staticTexts[name].tap()
        app.buttons["Add Expense"].tap()
        XCTAssertTrue(app.buttons["expense.people.continue"].waitForExistence(timeout: 5))
        app.buttons["expense.people.continue"].tap()
        XCTAssertTrue(app.buttons["capture.scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose Photo"].exists)
        XCTAssertFalse(app.textFields["expense.name"].exists)
        shot(app, "Trip capture choices")
        app.buttons["bill.currency"].tap(); app.buttons["XCG"].tap()
        app.buttons["Manual Entry"].tap()
        XCTAssertTrue(app.navigationBars["Review Receipt"].waitForExistence(timeout: 5))
        app.buttons["Add Item"].tap()
        app.textFields["Item name"].tap(); app.textFields["Item name"].typeText("Beach taxi")
        app.textFields["0.00"].tap(); app.textFields["0.00"].typeText("100")
        app.buttons["Add"].tap()
        app.navigationBars.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Who's Splitting?"].waitForExistence(timeout: 5))
        app.textFields["record.rate"].tap(); app.textFields["record.rate"].typeText("0.56")
        app.buttons["keyboard.dismiss"].tap()
        shot(app, "Trip receipt split settings")
        app.buttons["split.even"].tap()
        app.swipeUp()
        app.buttons["Calculate"].tap()
        shot(app, "Converted receipt results")
        app.navigationBars["Results"].buttons["Save to trip"].tap()
        XCTAssertTrue(app.staticTexts["You're owed USD 28.00"].waitForExistence(timeout: 5))
        app.buttons["Record Payment"].tap()
        app.buttons["record.currency"].tap(); app.buttons["XCG · Caribbean guilder"].tap()
        app.textFields["record.rate"].tap(); app.textFields["record.rate"].typeText("0.56")
        app.textFields["Amount"].tap(); app.textFields["Amount"].typeText("25")
        app.swipeUp()
        shot(app, "Record payment")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["You're owed USD 14.00"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.recent"].waitForExistence(timeout: 10))
        app.buttons["home.recent"].tap()
        XCTAssertTrue(app.staticTexts["You're owed USD 14.00"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.collectionViews.staticTexts["Beach taxi"].tap()
        app.buttons["expense.people.continue"].tap()
        XCTAssertEqual(app.textFields["record.rate"].value as? String, "0.56")
        app.buttons["split.items"].tap()
        shot(app, "By items assignment controls")
        XCTAssertTrue(app.navigationBars["Assign Items"].waitForExistence(timeout: 5))
    }
    @MainActor func testStandaloneCurrencyAndReceipt() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.buttons["home.bill"].tap()
        app.buttons["bill.currency"].tap(); app.buttons["XCG"].tap()
        shot(app, "Standalone bill opening")
        app.buttons["Manual Entry"].tap()
        XCTAssertTrue(app.navigationBars["Review Receipt"].waitForExistence(timeout: 5))
        shot(app, "Standalone XCG receipt")
    }
}
