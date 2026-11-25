import XCTest

/// Re-signs a smoke-test simulator in to iCloud by driving the system Settings app.
///
/// Simulator iCloud sessions expire on their own (cloudd starts failing every call with
/// `AuthTokenError 2011`), and the only cure is a full sign-out and sign-in in Settings.
/// On a simulator that has signed in to the same Apple ID before, that sign-in does not
/// ask for a two-factor code, so it can run unattended.
///
/// Driven by `Scripts/sim-icloud-relogin.sh`, which reads the Apple ID and password from
/// the Mac's login Keychain. The password never appears in the environment or the
/// repository: the script writes it to a 0600 temp file, passes only that file's path in
/// `SIM_ICLOUD_SECRET_FILE`, and deletes the file (and this run's result bundle) when
/// the test ends. Self-skips when the variables are missing, so the ordinary UI suite
/// (and CI) never touches Settings.
///
/// Settings changes its screens between iOS releases, so instead of a fixed script the
/// test looks at whatever is on screen each pass and takes the step that fits (sign
/// out, confirm, type the Apple ID, type the password, agree, merge), until the
/// account page shows the Apple ID again. Labels are matched in English and Chinese.
final class SimulatorICloudSignInTests: XCTestCase {
    private var settings: XCUIApplication!
    private var springboard: XCUIApplication!
    private var appleID = ""
    private var password = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let id = env["SIM_ICLOUD_APPLE_ID"], !id.isEmpty,
              let secretPath = env["SIM_ICLOUD_SECRET_FILE"], !secretPath.isEmpty else {
            throw XCTSkip("Runs only from Scripts/sim-icloud-relogin.sh.")
        }
        appleID = id
        password = try String(contentsOfFile: secretPath, encoding: .utf8)
            .trimmingCharacters(in: .newlines)
        XCTAssertFalse(password.isEmpty, "The Keychain password read by the script is empty.")
        settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// `SIM_ICLOUD_MODE`:
    /// - `signout`: sign out only. On iOS 26 the simulator restarts right after the
    ///   sign-out goes through, which kills this runner, so the script runs sign-in as a
    ///   second invocation once the simulator is back.
    /// - `signin-after-signout`: sign in, and fail if an account is already there (the
    ///   sign-out did not take, so the expired session would still be in place).
    /// - `signin`: sign in if needed (for a simulator that is already signed out).
    /// - `relogin` (default): both, in one go, where the simulator does not restart.
    func testReSignInToICloud() throws {
        let mode = ProcessInfo.processInfo.environment["SIM_ICLOUD_MODE"] ?? "relogin"
        settings.terminate()
        settings.launch()
        screenBounds = settings.windows.firstMatch.frame

        if mode == "signout" || mode == "relogin" {
            signOutIfSignedIn()
        }
        if mode == "signout" { return }
        signIn(requireSignedOut: mode == "signin-after-signout")
        dump("signed-in")
    }

    // MARK: - Sign out

    private func signOutIfSignedIn() {
        goToSettingsRoot()
        guard let accountRow = signedInAccountRow() else {
            log("No signed-in account row on the Settings root; skipping sign-out.")
            return
        }
        accountRow.tapCenter()

        let signOut = button(matching: ["Sign Out", "退出登录"])
        scrollUntilHittable(signOut)
        guard signOut.isOnScreen else {
            dump("no-sign-out-button")
            XCTFail("Found the account page but no Sign Out button.")
            return
        }
        signOut.tapCenter()

        // Then a series of prompts, in an order that varies by iOS version: the
        // Find My password alert, "keep a copy of your data" with a Sign Out button,
        // and an "Are you sure?" confirmation. Answer whatever shows up until the
        // Settings root offers sign-in again.
        let deadline = Date(timeIntervalSinceNow: 180)
        while Date() < deadline {
            if signInEntry().exists { log("Signed out."); return }
            if fillPasswordPromptIfShown() { continue }
            // iOS 26 first offers "Erase This iPhone" vs "Sign Out Without Erasing"
            // (抹掉此 iPhone / 退出登录但不抹掉). Only ever take the non-erasing one.
            if tapSignOutWithoutErasing() { continue }
            // …which then explains what stays on the device, with Continue / Cancel. The
            // account page's Sign Out row stays in the tree underneath this sheet, so
            // Continue must win over "Sign Out" below.
            if tapFirst(["Continue", "继续"]) { continue }
            // "Turn Off" (Find My) only inside an alert: in Chinese the sheet's X close
            // button is also "关闭", and tapping it just dismisses the sign-out flow.
            if tapFirst(["Turn Off", "关闭"], alertsOnly: true) { continue }
            // Keep-a-copy sheet and the final confirmation both end in "Sign Out".
            if tapFirst(["Sign Out", "退出登录"], preferAlert: true) { continue }
            if tapFirst(["Keep on My iPhone", "保留在我的 iPhone 上"], preferAlert: true) { continue }
            sleep(2)
            goToSettingsRootIfIdle()
        }
        dump("sign-out-timeout")
        XCTFail("Sign-out did not finish within 3 minutes.")
    }

    // MARK: - Sign in

    private func signIn(requireSignedOut: Bool) {
        goToSettingsRoot()
        let entry = signInEntry()
        if !entry.waitForExistence(timeout: 10) {
            if signedInAccountRow() != nil {
                if requireSignedOut {
                    dump("still-signed-in")
                    XCTFail("Still signed in after the sign-out step; the old session was not replaced.")
                    return
                }
                log("Already signed in; nothing to do.")
                return
            }
            dump("no-sign-in-entry")
            XCTFail("Neither a sign-in entry nor an account row on the Settings root.")
            return
        }
        entry.tapCenter()

        var typedAppleID = false
        var typedPassword = false
        let deadline = Date(timeIntervalSinceNow: 300)
        while Date() < deadline {
            if isSignedInOnRoot() { log("Signed in as \(appleID)."); return }

            // Some versions first ask how to sign in.
            // iOS 26: "Use Another Apple Device" / "Sign in Manually" cards (cells with
            // identifiers, the card text is not their label).
            let manualCell = settings.cells["AUTH_MANUAL_SIGN_IN_CELL"]
            if manualCell.exists, manualCell.isOnScreen {
                log("Tap \"Sign in Manually\"")
                manualCell.tapCenter()
                sleep(2)
                continue
            }
            if tapFirst(["Sign In Manually", "Sign in Manually", "手动登录"]) { continue }

            if fillPasswordPromptIfShown() { continue }

            // Type the password once; afterwards the field stays on screen (keyboard
            // down) while Continue still needs a tap, which the steps below do.
            let secure = settings.secureTextFields.firstMatch
            if !typedPassword, secure.exists, secure.isOnScreen {
                secure.tapCenter()
                clearText(in: secure)
                secure.typeText(password)
                typedPassword = true
                tapContinue()
                sleep(3)
                continue
            }

            let emailField = settings.textFields.firstMatch
            if !typedAppleID, emailField.exists, emailField.isOnScreen {
                emailField.tapCenter()
                clearText(in: emailField)
                emailField.typeText(appleID)
                tapContinue()
                typedAppleID = true
                sleep(3)
                continue
            }

            // Post-sign-in prompts: terms, merge local data, iPhone passcode, etc.
            if tapFirst(["Agree", "同意"], preferAlert: true) { continue }
            if tapFirst(["Merge", "合并"], preferAlert: true) { continue }
            if tapFirst(["Don't Merge", "不合并"], preferAlert: true) { continue }
            if tapFirst(["Not Now", "以后", "稍后"], preferAlert: true) { continue }
            if tapFirst(["Continue", "继续"]) { continue }
            if tapFirst(["Done", "完成"]) { continue }

            sleep(2)
            goToSettingsRootIfIdle()
        }
        dump("sign-in-timeout")
        XCTFail("Sign-in did not finish within 5 minutes. If Settings asked for a verification code, sign in by hand once; later re-logins on this simulator skip it.")
    }

    // MARK: - Screen recognition

    /// The Settings root row that opens sign-in when no account is present.
    private func signInEntry() -> XCUIElement {
        let predicate = NSPredicate(format:
            "label CONTAINS[c] 'sign in to' OR label CONTAINS '登录 iPhone' OR label CONTAINS '登录你的'"
            // iOS 26 zh: "Apple账户、登录以访问iCloud数据、App Store、Apple服务等。"
            + " OR label CONTAINS '登录以访问'"
            + " OR label ==[c] 'Sign In' OR label == '登录' OR label == 'Apple Account' OR label == 'Apple 账户'")
        return settings.cells.matching(predicate).firstMatch.exists
            ? settings.cells.matching(predicate).firstMatch
            : settings.buttons.matching(predicate).firstMatch
    }

    /// The account row at the top of the Settings root when signed in: its label
    /// carries the account owner's name plus "Apple Account, iCloud…".
    private func signedInAccountRow() -> XCUIElement? {
        let predicate = NSPredicate(format:
            "(label CONTAINS 'Apple Account,' OR label CONTAINS 'iCloud' OR label CONTAINS 'Apple 账户、' OR label CONTAINS 'Apple账户、')"
            + " AND NOT (label CONTAINS[c] 'sign in' OR label CONTAINS '登录')")
        let row = settings.cells.matching(predicate).firstMatch
        if row.waitForExistence(timeout: 3) { return row }
        let button = settings.buttons.matching(predicate).firstMatch
        return button.exists ? button : nil
    }

    private func isSignedInOnRoot() -> Bool {
        // The sign-in sheet can sit on top of the root; only trust the root when no
        // text entry is in front of us.
        guard !settings.secureTextFields.firstMatch.exists,
              !settings.textFields.firstMatch.exists else { return false }
        return !signInEntry().exists && signedInAccountRow() != nil
    }

    // MARK: - Helpers

    /// A password alert (Find My on sign-out, "sign in again" on an expired session)
    /// owned by Settings or SpringBoard.
    private func fillPasswordPromptIfShown() -> Bool {
        for app in [settings!, springboard!] {
            let alert = app.alerts.firstMatch
            guard alert.exists else { continue }
            let field = alert.secureTextFields.firstMatch
            guard field.exists else { continue }
            field.tapCenter()
            field.typeText(password)
            for label in ["Turn Off", "关闭", "Sign In", "登录", "OK", "好", "Continue", "继续"] {
                let b = alert.buttons[label]
                if b.exists { b.tapCenter(); sleep(3); return true }
            }
            alert.buttons.element(boundBy: alert.buttons.count - 1).tapCenter()
            sleep(3)
            return true
        }
        return false
    }

    /// Submits the current sign-in step: with the keyboard up, its return key (labelled
    /// "continue" on iOS 26; the sheet's own Continue button sits under the keyboard),
    /// otherwise the visible Continue / Next / Sign In button.
    private func tapContinue() {
        let key = settings.keyboards.buttons.matching(NSPredicate(format:
            "label IN[c] {'return', 'go', 'next', 'continue', 'done', '继续', '下一步', '前往', '完成'}"))
            .firstMatch
        if key.exists {
            log("Tap keyboard \"\(key.label)\"")
            key.tapCenter()
            return
        }
        tapFirst(["Continue", "继续", "Next", "下一步", "Sign In", "登录"])
    }

    /// Taps the first hittable button whose label is one of `labels`, looking in
    /// alerts / sheets first when `preferAlert` is set. Returns whether it tapped.
    @discardableResult
    private func tapFirst(_ labels: [String], preferAlert: Bool = false, alertsOnly: Bool = false) -> Bool {
        var scopes: [XCUIElement] = []
        if preferAlert || alertsOnly {
            scopes += [settings.alerts.firstMatch, springboard.alerts.firstMatch, settings.sheets.firstMatch]
        }
        if !alertsOnly { scopes.append(settings) }
        for scope in scopes where scope.exists {
            for label in labels {
                // A label can match several buttons at once (the sign-in sheet's 继续 and
                // the keyboard's 继续 key), and a plain `buttons[label]` then fails the
                // test on its first frame read; take the first one on screen instead.
                let matches = scope.buttons.matching(identifier: label)
                for i in 0..<matches.count {
                    let b = matches.element(boundBy: i)
                    if b.exists, b.isOnScreen {
                        log("Tap \"\(label)\"")
                        b.tapCenter()
                        sleep(2)
                        return true
                    }
                }
            }
        }
        return false
    }

    /// The "sign out but keep this iPhone's data" choice on the erase-or-not sheet.
    /// Matched by its own wording and never by anything that mentions erasing alone, so
    /// the test cannot wipe the simulator.
    private func tapSignOutWithoutErasing() -> Bool {
        let b = settings.buttons.matching(NSPredicate(format:
            "label BEGINSWITH '退出登录但' OR (label CONTAINS[c] 'sign out' AND"
            + " (label CONTAINS[c] 'without eras' OR label CONTAINS[c] 'don\\'t erase' OR label CONTAINS[c] 'not erase'))"))
            .firstMatch
        guard b.exists, b.isOnScreen,
              !(b.label.hasPrefix("抹掉") || b.label.lowercased().hasPrefix("erase")) else { return false }
        log("Tap \"\(b.label)\"")
        b.tapCenter()
        sleep(2)
        return true
    }

    private func button(matching labels: [String]) -> XCUIElement {
        settings.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isOnScreen) {
            settings.swipeUp()
        }
    }

    private func clearText(in field: XCUIElement) {
        guard let value = field.value as? String, !value.isEmpty,
              value != field.placeholderValue else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }

    private func goToSettingsRoot() {
        for _ in 0..<5 {
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            guard settings.navigationBars.count > 0, back.exists, back.isOnScreen,
                  back.label != "Search", back.label != "搜索" else { break }
            // The root's nav bar has no back button; stop once its title shows.
            if settings.navigationBars["Settings"].exists || settings.navigationBars["设置"].exists { break }
            back.tapCenter()
        }
    }

    /// When nothing on screen matched, a pushed page may be hiding the root.
    private func goToSettingsRootIfIdle() {
        guard !settings.alerts.firstMatch.exists, !settings.sheets.firstMatch.exists,
              !springboard.alerts.firstMatch.exists else { return }
        goToSettingsRoot()
    }

    private func log(_ message: String) { print("[sim-icloud] \(message)") }

    /// Screenshot + accessibility tree, so a changed Settings layout is quick to fix.
    /// The secure fields never expose their text, so the password is not in either.
    private func dump(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        print("[sim-icloud] --- \(name): Settings tree ---\n\(settings.debugDescription)")
        if springboard.alerts.firstMatch.exists {
            print("[sim-icloud] --- \(name): SpringBoard alert ---\n\(springboard.alerts.firstMatch.debugDescription)")
        }
    }
}

/// The screen in Settings' coordinates, read once Settings is up.
nonisolated(unsafe) private var screenBounds = CGRect(x: 0, y: 0, width: 402, height: 874)

extension XCUIElement {
    /// `isHittable` raises a test failure ("Activation point invalid") instead of returning
    /// false for some Settings rows, e.g. Sign Out sitting under the home indicator on
    /// iOS 26. Judge by the frame instead: the centre must be on screen, clear of the
    /// status bar and the home indicator.
    fileprivate var isOnScreen: Bool {
        guard exists else { return false }
        let f = frame
        guard !f.isEmpty else { return false }
        let center = CGPoint(x: f.midX, y: f.midY)
        guard screenBounds.insetBy(dx: 0, dy: 24).contains(center) else { return false }
        // A button under the on-screen keyboard is not tappable: the tap lands on a key.
        if elementType != .key {
            let keyboard = XCUIApplication(bundleIdentifier: "com.apple.Preferences").keyboards.firstMatch
            if keyboard.exists, keyboard.frame.contains(center) { return false }
        }
        return true
    }

    /// Taps the frame's centre, which works where `tap()` trips over the same activation
    /// point check.
    fileprivate func tapCenter() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
