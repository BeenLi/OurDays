import XCTest

final class CoupleCalendarUITests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        dismissInitialProfilePromptIfNeeded(in: app)

        XCTAssertTrue(app.buttons["compact-date-picker-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["compact-create-invite-button"].exists)
        XCTAssertFalse(app.buttons["compact-sync-button"].exists)
    }

    func testSwipingContentAreaChangesSelectedDate() {
        let app = XCUIApplication()
        app.launch()
        dismissInitialProfilePromptIfNeeded(in: app)

        let datePickerButton = app.buttons["compact-date-picker-button"]
        XCTAssertTrue(datePickerButton.waitForExistence(timeout: 3))
        let initialTitle = datePickerButton.value as? String

        app.swipeLeft()

        XCTAssertNotEqual(datePickerButton.value as? String, initialTitle)
    }

    func testFirstLaunchGuidanceNavigatesToCalendarSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--sharecal-reset-user-defaults"]
        app.launch()
        dismissInitialProfilePromptIfNeeded(in: app)

        XCTAssertFalse(app.buttons["Load Sample Schedule"].exists)
        XCTAssertFalse(app.buttons["加载示例日程"].exists)

        let guidanceButton = app.buttons["calendar-setup-guidance-button"]
        XCTAssertTrue(guidanceButton.waitForExistence(timeout: 3))
        guidanceButton.tap()

        XCTAssertTrue(app.buttons["settings-calendar-access-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Calendar Access"].exists || app.staticTexts["日历访问"].exists)
    }

    /// End-to-end UI assertion for the two-simulator pairing smoke test
    /// (Scripts/dev-pairing-smoke.sh). By the time this runs the script has paired
    /// THIS device and imported the owner's seeded event into the local SwiftData
    /// cache, so launching the app must actually RENDER that event on the calendar —
    /// proving the synced background state reaches the UI, not just the stored
    /// pairing fields the script's other assertions check.
    ///
    /// Self-skips unless the runner sets SHARECAL_SMOKE_UI (the script passes
    /// `TEST_RUNNER_SHARECAL_SMOKE_UI=1`), so the ordinary UI suite stays green on an
    /// unpaired simulator where no synced event exists.
    func testPairedPartnerCalendarShowsOwnerEvent() throws {
        guard ProcessInfo.processInfo.environment["SHARECAL_SMOKE_UI"] != nil else {
            throw XCTSkip("Runs only inside Scripts/dev-pairing-smoke.sh against a paired, synced device.")
        }

        let app = XCUIApplication()
        // Seed onboarding flags and force a fresh import so the calendar reflects the
        // latest shared-zone state. The imported mirror is also persisted in SwiftData
        // from the earlier smoke steps, so the assertion still holds if the sync is slow.
        app.launchArguments = ["-ShareCalSeedProfileName", "SmokePartner", "-ShareCalForceSync"]
        app.launch()

        // Mirrors ShareCalSmokeTestEventPlan.title; app sources are not compiled into
        // the UI-test target, so the string is intentionally duplicated here.
        let ownerEventTitle = "ShareCal E2E Smoke Test"
        // Match any element whose label contains the title: depending on the active
        // calendar mode the title is either a standalone Text or merged into a
        // combined accessibility label, so a contains-predicate is the robust query.
        let eventPredicate = NSPredicate(format: "label CONTAINS %@", ownerEventTitle)
        let ownerEvent = app.descendants(matching: .any).matching(eventPredicate).firstMatch

        // A fresh post-pairing launch stacks modals over the calendar that appear
        // asynchronously: the system notification-permission alert (owned by SpringBoard)
        // and the "set a note name for your partner" sheet that opens once the forced
        // sync resolves pairing. Dismiss whichever modal is up on each poll until the
        // owner's event becomes reachable.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date(timeIntervalSinceNow: 120)
        var appeared = ownerEvent.waitForExistence(timeout: 3)
        while !appeared && Date() < deadline {
            dismissBlockingModal(app: app, springboard: springboard)
            appeared = ownerEvent.waitForExistence(timeout: 3)
        }

        // The event can be found while a modal is still up (it exists in the tree behind
        // the alert), so clear any lingering modal before capturing, to keep the saved
        // screenshot a bare calendar showing the owner's event rather than a permission
        // alert on top. Artifact polish only; does not affect the assertion.
        if appeared {
            for _ in 0..<4 { dismissBlockingModal(app: app, springboard: springboard) }
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "partner-calendar-after-pairing"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(appeared, "Partner's calendar must render the owner's synced event '\(ownerEventTitle)'.")
    }

    /// Dismisses one blocking modal if present. The seed-profile launch args suppress
    /// the in-app advisory sheets, so in practice this only clears the SpringBoard-owned
    /// notification-permission alert (which has no settings flag). The in-app dismiss
    /// buttons are kept as a defensive fallback. Taps at most one per call so the caller
    /// can re-check for the target between dismissals.
    private func dismissBlockingModal(app: XCUIApplication, springboard: XCUIApplication) {
        for label in ["允许", "Allow", "不允许", "Don’t Allow"] {
            let button = springboard.buttons[label]
            if button.exists { button.tap(); return }
        }
        for label in ["跳过", "Skip", "继续", "Continue"] {
            let button = app.buttons[label]
            if button.exists { button.tap(); return }
        }
    }

    private func dismissInitialProfilePromptIfNeeded(in app: XCUIApplication) {
        let englishSkipButton = app.buttons["Skip"]
        if englishSkipButton.waitForExistence(timeout: 1) {
            englishSkipButton.tap()
            return
        }

        let chineseSkipButton = app.buttons["跳过"]
        if chineseSkipButton.waitForExistence(timeout: 1) {
            chineseSkipButton.tap()
        }
    }
}
