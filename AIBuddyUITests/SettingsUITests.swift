import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var settings: XCUIElement {
        app.windows.containing(.staticText, identifier: "settings-heading").firstMatch
    }
    private func cleanup() {
        guard let app, app.state == .runningForeground || app.state == .runningBackground else { return }
        if settings.exists { settings.buttons[XCUIIdentifierCloseWindow].click() }
        app.terminate()
    }
    private func launch(_ scenario: String, shortcut: Bool = false) {
        app = XCUIApplication()
        app.launchEnvironment["AI_BUDDY_UI_TEST"] = scenario
        app.launch()
        addTeardownBlock { [weak self] in await self?.cleanup() }
        XCTAssertTrue(app.buttons["nav-settings"].waitForExistence(timeout: 10))
        if shortcut { app.typeKey(",", modifierFlags: .command) }
        else { app.buttons["nav-settings"].click() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }
    private func assertStatus(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let status = settings.staticTexts["github-status"]
        let expected = NSPredicate(format: "value == %@", value)
        expectation(for: expected, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(status.value as? String, value, file: file, line: line)
    }
    func testSidebarSettingsStatusAndConfirmedRemoval() {
        launch("connected")
        assertStatus("Connected")
        XCTAssertTrue(settings.staticTexts["github-account"].exists)
        XCTAssertTrue(settings.buttons["settings-manage-github"].exists)
        settings.buttons["settings-remove-github"].click()
        XCTAssertTrue(settings.sheets.firstMatch.waitForExistence(timeout: 5))
        settings.sheets.buttons["Cancel"].click()
        assertStatus("Connected")
        settings.buttons["settings-remove-github"].click()
        settings.sheets.buttons["Remove"].click()
        assertStatus("Not connected")
        XCTAssertFalse(settings.staticTexts["github-account"].exists)
        settings.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pr-10"].exists)
    }
    func testSettingsShortcutAndConnectingFromSettings() {
        launch("disconnected", shortcut: true)
        assertStatus("Not connected")
        settings.buttons["connect-github"].click()
        XCTAssertTrue(settings.staticTexts["device-code"].waitForExistence(timeout: 5))
        assertStatus("Connecting")
        settings.buttons["cancel-connection"].click()
        assertStatus("Not connected")
    }
    func testSettingsShowsExpiredLimitedAndUnconfiguredStatus() {
        for (scenario, status) in [("expired", "Reconnect required"), ("partial", "Limited access"), ("unconfigured", "Not configured")] {
            launch(scenario)
            assertStatus(status)
            let attachment = XCTAttachment(screenshot: settings.screenshot())
            attachment.name = "Settings — \(scenario)"
            attachment.lifetime = .keepAlways
            add(attachment)
            settings.buttons[XCUIIdentifierCloseWindow].click()
            app.terminate()
        }
    }
    func testFailedRemovalShowsFailureInsteadOfSuccess() {
        launch("removal-error")
        assertStatus("Connected")
        settings.buttons["settings-remove-github"].click()
        settings.sheets.buttons["Remove"].click()
        assertStatus("Removal incomplete")
        XCTAssertTrue(settings.buttons["settings-remove-github"].isEnabled)
    }
    func testConnectedSettingsScreenshot() {
        launch("connected")
        assertStatus("Connected")
        let attachment = XCTAttachment(screenshot: settings.screenshot())
        attachment.name = "Settings — GitHub connection"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
