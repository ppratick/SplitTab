import XCTest

final class ReceiptSettingsTests: XCTestCase {
    @MainActor func testKeyPersistsAcrossLaunchesAndCanBeRemoved() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 10))
        app.buttons["home.settings"].tap()
        // Never overwrite a developer's existing credential.
        if app.buttons["Remove Key"].exists { throw XCTSkip("This simulator already has a saved key") }
        let field = app.secureTextFields["settings.apiKey"]
        field.tap(); field.typeText("sk-local-test-not-a-real-key")
        app.buttons["Save Key"].tap()
        XCTAssertTrue(app.staticTexts["Key saved on this device"].exists)
        app.terminate(); app.launch()
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.staticTexts["Key saved on this device"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].exists)
        app.secureTextFields["settings.apiKey"].tap()
        app.secureTextFields["settings.apiKey"].typeText("sk-local-replacement-not-a-real-key")
        app.buttons["Replace Key"].tap()
        XCTAssertTrue(app.staticTexts["Key saved on this device"].exists)
        app.buttons["Remove Key"].tap()
        app.sheets.buttons["Remove Key"].tap()
        XCTAssertTrue(app.staticTexts["No saved key"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.staticTexts["No saved key"].waitForExistence(timeout: 5))
    }
}
