import XCTest

final class TripResultsTests: XCTestCase {
    @MainActor func testAssignedItemsOpenResultsAndSaveToTrip() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.buttons["home.trips"].tap(); app.buttons["Create Trip"].tap()
        let name = "Receipt " + String(UUID().uuidString.prefix(6))
        app.textFields["Trip name"].tap(); app.textFields["Trip name"].typeText(name)
        let person = app.textFields.matching(identifier: "Name").element(boundBy: 1)
        person.tap(); person.typeText("Alex")
        app.buttons["Create"].tap()
        for _ in 0..<25 {
            if app.collectionViews.staticTexts[name].exists { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        app.collectionViews.staticTexts[name].tap()
        app.buttons["Add Expense"].tap(); app.buttons["expense.people.continue"].tap()
        app.buttons["Manual Entry"].tap()
        XCTAssertTrue(app.navigationBars["Review Receipt"].waitForExistence(timeout: 5))
        app.buttons["Add Item"].tap()
        app.textFields["Item name"].tap(); app.textFields["Item name"].typeText("Pizza")
        app.textFields["0.00"].tap(); app.textFields["0.00"].typeText("20")
        app.buttons["Add"].tap()
        let price = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "receipt.price.")).firstMatch
        price.doubleTap(); price.typeText("25")
        XCTAssertEqual(price.value as? String, "25")
        app.navigationBars.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Who's Splitting?"].waitForExistence(timeout: 5))
        app.buttons["split.items"].tap()
        app.swipeUp()
        app.buttons["Assign Items"].tap()
        app.buttons["Alex"].tap()
        app.buttons["See Results"].tap()
        XCTAssertTrue(app.navigationBars["Results"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Assignments ready"].exists)
        XCTAssertFalse(app.buttons["Use Receipt"].exists)
        XCTAssertTrue(app.buttons["copy.all.breakdown"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Trip itemized results"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars["Results"].buttons["Save to trip"].tap()
        XCTAssertTrue(app.buttons["Add Expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You're owed USD 25.00"].exists)
        app.terminate(); app.launch()
        app.buttons["home.recent"].tap()
        XCTAssertTrue(app.staticTexts["You're owed USD 25.00"].waitForExistence(timeout: 5))
    }
}
