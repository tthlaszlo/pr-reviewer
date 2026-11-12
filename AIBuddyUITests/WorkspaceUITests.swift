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
    func testMyPullRequestReviewsAndBackPreserveFilter() {
        let app = launch("connected")
        XCTAssertTrue(app.buttons["nav-authored"].waitForExistence(timeout: 10))
        app.buttons["nav-authored"].click()
        let pull = app.buttons["pr-10"]
        XCTAssertTrue(pull.waitForExistence(timeout: 10))
        app.textFields["pr-filter"].click()
        app.textFields["pr-filter"].typeText("native")
        pull.click()
        XCTAssertTrue(app.staticTexts["Looks good to me!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Approved"].exists)
        XCTAssertTrue(app.staticTexts["Changes requested"].exists)
        XCTAssertTrue(app.staticTexts["This can fail when offline."].exists)
        XCTAssertTrue(app.staticTexts["Sources/Client.swift:42"].exists)
        app.buttons["refresh-reviews"].click()
        XCTAssertTrue(app.staticTexts["Looks good to me!"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "My pull request reviews"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["back-to-my-prs"].click()
        XCTAssertTrue(pull.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["pr-filter"].value as? String, "native")
    }
    func testFormattedReviewDesignAndDisclosure() {
        let app = launch("reviews-design")
        XCTAssertTrue(app.buttons["nav-authored"].waitForExistence(timeout: 10))
        app.buttons["nav-authored"].click()
        XCTAssertTrue(app.buttons["pr-10"].waitForExistence(timeout: 10))
        app.buttons["pr-10"].click()
        XCTAssertTrue(app.staticTexts["greptile-apps[bot]"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BOT"].exists)
        XCTAssertTrue(app.staticTexts["Review summary"].exists)
        XCTAssertTrue(app.staticTexts["P1 Fresh accounts still wait"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "<img")).firstMatch.exists)
        let prompt = app.buttons["review-details-toggle"].firstMatch
        if !prompt.isHittable { app.scrollViews["review-history"].swipeUp() }
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertEqual(prompt.value as? String, "Collapsed")
        prompt.click()
        XCTAssertEqual(prompt.value as? String, "Expanded")
        let code = app.staticTexts["review-code-text"].firstMatch
        if !code.exists { app.scrollViews["review-history"].swipeUp() }
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(code.label.contains("This is a comment left during a code review."))
        prompt.click()
        XCTAssertEqual(prompt.value as? String, "Collapsed")
        XCTAssertFalse(code.exists)
        prompt.click()
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Focus reviewer groups and formatted feedback"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testReviewEmptyErrorAndPartialStates() {
        for scenario in ["reviews-empty", "reviews-error", "reviews-partial"] {
            let app = launch(scenario)
            XCTAssertTrue(app.buttons["nav-authored"].waitForExistence(timeout: 10))
            app.buttons["nav-authored"].click()
            XCTAssertTrue(app.buttons["pr-10"].waitForExistence(timeout: 10))
            app.buttons["pr-10"].click()
            if scenario == "reviews-empty" {
                XCTAssertTrue(app.staticTexts["No reviews yet"].waitForExistence(timeout: 5))
            } else if scenario == "reviews-error" {
                XCTAssertTrue(app.buttons["retry-reviews"].waitForExistence(timeout: 5))
                app.buttons["retry-reviews"].click()
                XCTAssertTrue(app.buttons["retry-reviews"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["No reviews yet"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["Review history is incomplete. Open this PR on GitHub to see the full history."].waitForExistence(timeout: 5))
            }
            app.buttons["nav-reviews"].click()
            XCTAssertTrue(app.buttons["group-awaiting"].waitForExistence(timeout: 5))
            app.terminate()
        }
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
        XCTAssertTrue(partial.buttons["show-access-help"].exists)
        partial.buttons["show-access-help"].click()
        XCTAssertTrue(partial.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(partial.sheets.buttons["open-access-settings"].exists)
        XCTAssertTrue(partial.sheets.buttons["reauthorize-github"].exists)
    }
    func testPermissionErrorAndDisconnect() {
        let app = launch("error")
        XCTAssertTrue(app.staticTexts["Set up GitHub access"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["check-github-access"].isEnabled)
        app.buttons["disconnect"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["Disconnect"].click()
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 5))
    }
    func testExpiredAccessShowsReconnectOnBothPages() {
        let app = launch("expired")
        XCTAssertTrue(app.staticTexts["Reconnect GitHub to continue"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["group-awaiting"].exists)
        app.buttons["nav-authored"].click()
        XCTAssertTrue(app.staticTexts["Reconnect GitHub to continue"].exists)
        app.buttons["connect-github"].click()
        XCTAssertTrue(app.staticTexts["device-code"].waitForExistence(timeout: 5))
        app.buttons["cancel-connection"].click()
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reconnect GitHub to continue"].exists)
    }
    func testRestrictedPageDoesNotBlockOtherPages() {
        let app = launch("reviews-restricted")
        XCTAssertTrue(app.staticTexts["Set up GitHub access"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["open-access-settings"].exists)
        app.buttons["nav-authored"].click()
        XCTAssertTrue(app.buttons["pr-10"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open-access-settings"].exists)
        app.buttons["nav-reviews"].click()
        app.buttons["reauthorize-github"].click()
        XCTAssertTrue(app.staticTexts["device-code"].waitForExistence(timeout: 5))
        app.buttons["cancel-connection"].click()
        XCTAssertTrue(app.staticTexts["Set up GitHub access"].waitForExistence(timeout: 5))
    }
    func testConnectionGuideOnBothPagesAndCopyCode() {
        let app = launch("disconnected")
        XCTAssertTrue(app.buttons["connect-github"].waitForExistence(timeout: 10))
        app.buttons["nav-authored"].click()
        XCTAssertTrue(app.staticTexts["Connect GitHub to get started"].exists)
        XCTAssertFalse(app.textFields["pr-filter"].exists)
        app.buttons["connect-github"].click()
        XCTAssertTrue(app.buttons["copy-device-code"].waitForExistence(timeout: 5))
        app.buttons["copy-device-code"].click()
        XCTAssertEqual(app.buttons["copy-device-code"].label, "Copied")
        XCTAssertTrue(app.buttons["open-device-github"].exists)
        app.buttons["nav-reviews"].click()
        XCTAssertTrue(app.staticTexts["device-code"].exists)
    }
    func testEmptyPartialAccessDoesNotClaimAllCaughtUp() {
        let app = launch("partial-empty")
        XCTAssertTrue(app.staticTexts["No accessible pull requests in this view"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["show-access-help"].exists)
        XCTAssertFalse(app.staticTexts["You're all caught up"].exists)
    }
    func testAccessGuidanceScreenshots() {
        for scenario in ["disconnected", "device-code", "expired", "reviews-restricted", "partial"] {
            let app = launch(scenario == "device-code" ? "disconnected" : scenario)
            let element = scenario == "partial" ? app.buttons["show-access-help"] :
                scenario == "reviews-restricted" ? app.buttons["check-github-access"] : app.buttons["connect-github"]
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            if scenario == "device-code" {
                app.buttons["connect-github"].click()
                XCTAssertTrue(app.staticTexts["device-code"].waitForExistence(timeout: 5))
            }
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.name = "GitHub access — \(scenario)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
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
