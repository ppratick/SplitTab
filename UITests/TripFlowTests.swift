import XCTest

final class TripFlowTests: XCTestCase {
    // Run after the main smoke test, with CURRENT_PROJECT_VERSION=2, to verify
    // an ordinary install-over-existing-data upgrade without uninstalling.
    @MainActor func testZExistingTripSurvivesUpdate() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["home.trips"].waitForExistence(timeout: 15))
        app.buttons["home.trips"].tap()
        XCTAssertTrue(app.collectionViews.staticTexts["You're owed USD 40.00"].firstMatch.waitForExistence(timeout: 15))
        app.collectionViews.staticTexts["You're owed USD 40.00"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add Expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You're owed USD 40.00"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Dinner"].exists)
        XCTAssertTrue(app.staticTexts["Alex → Me: USD 40.00"].exists || app.staticTexts["Sam → Me: USD 40.00"].exists)
        let history = XCTAttachment(screenshot: app.screenshot()); history.name = "History after app update"; history.lifetime = .keepAlways; add(history)
    }

    @MainActor func testTripExpensePaymentAndRelaunch() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launch()
        XCTAssertTrue(app.buttons["home.trips"].waitForExistence(timeout: 15))
        app.buttons["home.trips"].tap()
        XCTAssertTrue(app.buttons["Create Trip"].waitForExistence(timeout: 15))
        app.buttons["Create Trip"].tap()
        let name = "UI Weekend " + String(UUID().uuidString.prefix(6))
        app.textFields["Trip name"].tap(); app.textFields["Trip name"].typeText(name)
        let names = app.textFields.matching(identifier: "Name")
        names.element(boundBy: 1).tap(); names.element(boundBy: 1).typeText("Alex")
        app.buttons["Add Participant"].tap()
        names.element(boundBy: 2).tap(); names.element(boundBy: 2).typeText("Sam")
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
        app.buttons["Manual Entry"].tap()
        XCTAssertTrue(app.navigationBars["Review Receipt"].waitForExistence(timeout: 5))
        app.buttons["Add Item"].tap()
        app.textFields["Item name"].tap(); app.textFields["Item name"].typeText("Dinner")
        app.textFields["0.00"].tap(); app.textFields["0.00"].typeText("120")
        app.buttons["Add"].tap()
        app.navigationBars.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Who's Splitting?"].waitForExistence(timeout: 5))
        app.buttons["split.even"].tap()
        app.swipeUp()
        app.buttons["Calculate"].tap()
        app.navigationBars["Results"].buttons["Save to trip"].tap()
        XCTAssertTrue(app.staticTexts["You're owed USD 80.00"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Trip overview"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["Settle Up"].tap()
        XCTAssertTrue(app.staticTexts["Receives USD 80.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record payment from Alex to Me"].exists)
        XCTAssertTrue(app.buttons["Record payment from Sam to Me"].exists)
        app.buttons["settlement.copy.all.totals"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard"].exists)
        app.buttons["settlement.copy.all.breakdown"].tap()
        app.buttons["Copy repayments for Alex"].tap()
        app.buttons["settlement.copy.person.totals"].tap()
        app.buttons["Copy repayments for Alex"].tap()
        app.buttons["settlement.copy.person.breakdown"].tap()
        app.buttons["settlement.breakdown.Alex.Me"].tap()
        XCTAssertFalse(app.navigationBars["Record Payment"].exists)
        XCTAssertTrue(app.staticTexts.matching(identifier: "settlement.breakdown.Alex.Me").matching(NSPredicate(format: "label == %@", "Dinner")).firstMatch.isHittable)
        let settlement = XCTAttachment(screenshot: app.screenshot())
        settlement.name = "Grouped settlement with expense breakdown"; settlement.lifetime = .keepAlways; add(settlement)
        app.buttons["Record payment from Alex to Me"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["You're owed USD 40.00"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.trips"].waitForExistence(timeout: 15))
        app.buttons["home.trips"].tap()
        for _ in 0..<20 {
            if app.collectionViews.staticTexts[name].exists { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        app.collectionViews.staticTexts[name].tap()
        XCTAssertTrue(app.staticTexts["You're owed USD 40.00"].exists)
        let expenseRow = app.cells.containing(.staticText, identifier: "Dinner").firstMatch
        for _ in 0..<6 { if expenseRow.isHittable { break }; app.swipeUp() }
        expenseRow.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(expenseRow.exists)
        expenseRow.swipeLeft(); app.buttons["Delete"].tap()
        app.alerts.buttons["Delete Expense"].tap()
        XCTAssertTrue(app.staticTexts["No expenses yet"].waitForExistence(timeout: 5))
        let paymentRow = app.cells.containing(.staticText, identifier: "Alex → Me: USD 40.00").firstMatch
        for _ in 0..<6 { if paymentRow.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(paymentRow.exists)
        paymentRow.swipeLeft(); app.buttons["Delete"].tap()
        app.alerts.buttons["Delete Payment"].tap()
        XCTAssertTrue(app.staticTexts["No confirmed payments recorded"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Trips"].tap()
        app.buttons["Home"].tap()
        app.buttons["home.bill"].tap()
        XCTAssertTrue(app.buttons["Manual Entry"].waitForExistence(timeout: 5))
        app.buttons["Manual Entry"].tap()
        XCTAssertTrue(app.navigationBars["Review Receipt"].waitForExistence(timeout: 5))
    }
}
