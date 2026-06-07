import XCTest

final class CoupleCalendarUITests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["compact-date-picker-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["compact-create-invite-button"].exists)
        XCTAssertTrue(app.buttons["compact-sync-button"].exists)
        XCTAssertFalse(app.staticTexts["ShareCal"].exists)
    }
}
