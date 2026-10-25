import XCTest

final class OurDaysUITests: XCTestCase {
    /// Generous wait for an element that appears after an async UI state transition
    /// (e.g. sheet dismiss → root-flow re-evaluation → card render). On a loaded CI
    /// runner, `app.launch()` wait-for-idle alone has been seen to take ~45s, so a
    /// 3s wait straddling such a transition expires mid-render on a healthy app.
    private static let transitionTimeout: TimeInterval = 30

    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        dismissInitialProfilePromptIfNeeded(in: app)

        XCTAssertTrue(app.buttons["compact-date-picker-button"].waitForExistence(timeout: Self.transitionTimeout))
        XCTAssertTrue(app.buttons["compact-create-invite-button"].exists)
        XCTAssertFalse(app.buttons["compact-sync-button"].exists)
    }

    func testSwipingContentAreaChangesSelectedDate() {
        let app = XCUIApplication()
        app.launch()
        dismissInitialProfilePromptIfNeeded(in: app)

        let datePickerButton = app.buttons["compact-date-picker-button"]
        XCTAssertTrue(datePickerButton.waitForExistence(timeout: Self.transitionTimeout))
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
        XCTAssertTrue(guidanceButton.waitForExistence(timeout: Self.transitionTimeout))
        guidanceButton.tap()

        XCTAssertTrue(app.buttons["settings-calendar-access-button"].waitForExistence(timeout: Self.transitionTimeout))
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

        // Mirrors ShareCalSmokeTestEventPolicy.title; app sources are not compiled into
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

    /// Regression guard for the joint-event comment entry point: the green joint block
    /// must be tappable (it is now a Button, matching the regular lane events) and open
    /// the shared comment thread. Runs only inside the pairing smoke after the joint
    /// event + comment round-trip has been established. Self-skips otherwise.
    func testPairedPartnerCanOpenJointEventCommentThread() throws {
        guard ProcessInfo.processInfo.environment["SHARECAL_SMOKE_UI"] != nil else {
            throw XCTSkip("Runs only inside Scripts/dev-pairing-smoke.sh after the joint-comment round-trip.")
        }

        let app = XCUIApplication()
        app.launchArguments = ["-ShareCalSeedProfileName", "SmokePartner", "-ShareCalForceSync"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Reach the joint block via the real user flow rather than assuming the joint event
        // is on "today": open the 邀请 (Invites) tab, tap the accepted invitation row (which
        // focuses the calendar on the invitation's own date), then tap the green joint block.
        // This is date-independent — the smoke event need not fall on the current day.
        let invitesTab = app.buttons["邀请"]
        let invitesDeadline = Date(timeIntervalSinceNow: 180)
        var invitesReady = invitesTab.waitForExistence(timeout: 3)
        while !invitesReady && Date() < invitesDeadline {
            dismissBlockingModal(app: app, springboard: springboard)
            invitesReady = invitesTab.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(invitesReady, "The Invites tab must be reachable.")
        invitesTab.tap()

        // The accepted invitation row carries the smoke event title. Wait for it (the CloudKit
        // invitation import is async after the forced sync), then tap to focus it in calendar.
        let invitationRow = app.staticTexts["ShareCal E2E Smoke Test"].firstMatch
        var rowReady = invitationRow.waitForExistence(timeout: 3)
        let rowDeadline = Date(timeIntervalSinceNow: 180)
        while !rowReady && Date() < rowDeadline {
            // Re-pull to refresh the invites list while the import lands.
            invitesTab.tap()
            rowReady = invitationRow.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(rowReady, "The accepted invitation must appear in the Invites tab.")
        invitationRow.tap()

        // Focusing navigates to the calendar on the invitation's date with the joint block
        // visible. Match the GREEN joint block specifically by its joint-schedule word
        // ("共同"/"Together"), which ordinary per-lane mirror events never carry.
        let jointPredicate = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "共同", "Together")
        let jointBlock = app.buttons.matching(jointPredicate).firstMatch
        let appeared = jointBlock.waitForExistence(timeout: 30)

        let calendarShot = XCTAttachment(screenshot: app.screenshot())
        calendarShot.name = "joint-event-focused-on-calendar"
        calendarShot.lifetime = .keepAlways
        add(calendarShot)

        XCTAssertTrue(appeared, "The green joint event block must render as a tappable element on its date.")

        jointBlock.tap()

        // Opening the joint detail must surface the shared comment thread's input field —
        // the same EventCommentsSection that regular events use. A bare calendar screen
        // has no text field, so its presence proves the detail (and comments) opened.
        let commentField = app.textFields.firstMatch
        let opened = commentField.waitForExistence(timeout: 15)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "joint-event-comment-thread"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(opened, "Tapping the joint event must open its comment thread (a comment input field).")
    }

    /// V1b: opening MY OWN ordinary event must show the partner's comment thread and a reply
    /// field — not just the "invite partner" action. Before the fix, my events opened as
    /// transient "display:" mirrors whose comment section was suppressed. Relies on a prior
    /// `-ShareCalSeedOrdinaryComment` launch having seeded+uploaded a partner comment on my
    /// fresh ordinary event "V1B Ordinary Event". Self-skips unless SHARECAL_SMOKE_UI is set.
    func testOwnOrdinaryEventShowsPartnerCommentAndReply() throws {
        guard ProcessInfo.processInfo.environment["SHARECAL_SMOKE_UI"] != nil else {
            throw XCTSkip("Runs only in the V1b ordinary-comment verification after the comment is seeded.")
        }

        let app = XCUIApplication()
        app.launchArguments = ["-ShareCalSeedProfileName", "SmokeOwner", "-ShareCalForceSync"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Duplicated literals: app sources aren't compiled into the UI-test target. The event is
        // created ~15 min from now (today), so the default day view shows it as a tappable button
        // whose accessibility label contains the title.
        let eventTitle = "V1B Ordinary Event"
        let commentBody = "V1B partner comment"
        let eventPredicate = NSPredicate(format: "label CONTAINS %@", eventTitle)
        let eventButton = app.buttons.matching(eventPredicate).firstMatch

        let deadline = Date(timeIntervalSinceNow: 180)
        var appeared = eventButton.waitForExistence(timeout: 5)
        while !appeared && Date() < deadline {
            dismissBlockingModal(app: app, springboard: springboard)
            appeared = eventButton.waitForExistence(timeout: 5)
        }
        if appeared { for _ in 0..<4 { dismissBlockingModal(app: app, springboard: springboard) } }

        XCTAssertTrue(appeared, "My seeded ordinary event '\(eventTitle)' must render on the calendar.")

        // The event is ~15 min from "now", near the bottom of the day timeline; scroll it into
        // view so the screenshot clearly shows the red dot on my own event block (req1).
        app.swipeUp()
        app.swipeUp()

        let calendarShot = XCTAttachment(screenshot: app.screenshot())
        calendarShot.name = "own-event-red-dot"
        calendarShot.lifetime = .keepAlways
        add(calendarShot)

        eventButton.tap()

        let comment = app.staticTexts[commentBody]
        let commentAppeared = comment.waitForExistence(timeout: 30)
        // The reply composer is the same EventCommentsSection input the joint detail uses.
        let replyField = app.textFields.firstMatch
        let replyAppeared = replyField.waitForExistence(timeout: 5)

        let detailShot = XCTAttachment(screenshot: app.screenshot())
        detailShot.name = "own-event-comment-thread"
        detailShot.lifetime = .keepAlways
        add(detailShot)

        XCTAssertTrue(commentAppeared, "Opening my own event must show the partner's comment ('\(commentBody)').")
        XCTAssertTrue(replyAppeared, "Opening my own event must offer a reply field.")
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
