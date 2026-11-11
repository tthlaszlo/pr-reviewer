import XCTest

@MainActor
final class WorkspaceUITests: XCTestCase {
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AI_BUDDY_UI_TEST"] = scenario
        app.launch()
        return app
    }
    func testNavigationGroupsAndFilter() {
        let app = launch("connected")
        let first = app.buttons["pr-10"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertEqual(first.label, "Improve GitHub synchronization")
        app.buttons["group-waiting"].click()
        XCTAssertTrue(app.buttons["pr-11"].waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
        app.buttons["group-requestedAgain"].click()
        XCTAssertTrue(app.buttons["pr-12"].waitForExistence(timeout: 5))
        let filter = app.textFields["pr-filter"]
        filter.click(); filter.typeText("absent")
        XCTAssertTrue(app.staticTexts["No matching pull requests"].exists)
        app.buttons["nav-authored"].click()
        XCTAssertTrue(app.buttons["pr-10"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["pr-10"].label, "My native macOS feature")
        XCTAssertFalse(app.buttons["group-waiting"].exists)
        XCTAssertFalse(app.staticTexts["No matching pull requests"].exists)
    }
    func testConnectionCodeAndCancellation() {
        let app = launch("disconnected")
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 10))
        app.buttons["connect-github"].click()
        XCTAssertTrue(app.staticTexts["device-code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["device-code"].value as? String, "ABCD-EFGH")
        app.buttons["cancel-connection"].click()
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["device-code"].exists)
    }
    func testUnconfiguredAppStillShowsWorkspace() {
        let app = launch("unconfigured")
        XCTAssertTrue(app.buttons["nav-reviews"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connect-github"].isEnabled)
        XCTAssertTrue(app.staticTexts["Connect GitHub to get started"].exists)
    }
    func testEmptyAndPartialResults() {
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["You're all caught up"].waitForExistence(timeout: 10))
        app.terminate()
        let partial = launch("partial")
        XCTAssertTrue(partial.buttons["pr-10"].waitForExistence(timeout: 10))
        XCTAssertTrue(partial.staticTexts["Team membership is unavailable. Team requests may be missing."].exists)
    }
    func testPermissionErrorAndDisconnect() {
        let app = launch("error")
        XCTAssertTrue(app.staticTexts["Pull requests could not be loaded"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["refresh"].isEnabled)
        app.buttons["disconnect"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["Disconnect"].click()
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 5))
    }
    func testFocusScreenshot() {
        let app = launch("connected")
        XCTAssertTrue(app.buttons["pr-10"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "AI Buddy — native Focus"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
