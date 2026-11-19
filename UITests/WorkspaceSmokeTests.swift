import XCTest

final class WorkspaceSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDeviceWorkspaceAndSettings() {
        let app = launchWorkspace(appearance: "Light")
        capture("Today-light", from: app)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Local Contacts"].exists)
        capture("Settings-light", from: app)
    }

    @MainActor
    func testReportAndResolveRobotIssue() {
        let app = launchWorkspace(appearance: "Dark")
        app.buttons["Report a Robot Issue"].tap()
        XCTAssertTrue(app.navigationBars["New Robot Issue"].waitForExistence(timeout: 8))
        let title = "Check connector " + String(UUID().uuidString.prefix(4))
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.exists)
        titleField.tap()
        titleField.typeText(title)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))

        app.tabBars.buttons["Pit"].tap()
        app.staticTexts["Robot Issues"].tap()
        let saved = app.staticTexts[title]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        saved.tap()
        XCTAssertTrue(app.navigationBars["Robot Issue"].waitForExistence(timeout: 8))
        capture("Robot-issue-dark", from: app)

        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Status")).firstMatch
        XCTAssertTrue(picker.exists)
        picker.tap()
        app.buttons["Resolved"].tap()
        let note = app.textFields["What fixed it?"].exists ? app.textFields["What fixed it?"] : app.textViews["What fixed it?"]
        note.tap()
        note.typeText("Reseated the connector.")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Robot Issues"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[title].exists)
    }

    @MainActor
    func testCompleteReadinessRun() {
        let app = launchWorkspace(appearance: "Dark")
        app.tabBars.buttons["Pit"].tap()
        app.staticTexts["Readiness Checklists"].tap()
        XCTAssertTrue(app.navigationBars["Readiness"].waitForExistence(timeout: 8))
        app.buttons["Pre-match"].tap()

        let items = ["Secure a charged battery", "Check connectors and fasteners", "Confirm starting configuration",
                     "Select the planned autonomous routine", "Verify controllers and Driver Station"]
        for item in items {
            let button = app.buttons[item]
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            if button.value as? String != "Checked" { button.tap() }
        }
        let complete = app.buttons["Complete Run"]
        if !complete.isHittable { app.swipeUp() }
        XCTAssertTrue(complete.isEnabled)
        complete.tap()
        XCTAssertTrue(app.staticTexts["Completed by"].waitForExistence(timeout: 8))
        capture("Readiness-dark", from: app)
    }

    @MainActor
    private func launchWorkspace(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-useDeviceWorkspace", "NO", "-appearance", appearance]
        app.launch()
        let open = app.buttons["Use On This Device"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        capture("Sign-in-" + appearance.lowercased(), from: app)
        open.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func capture(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
