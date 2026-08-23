import XCTest

/// Smoke test: the app launches and renders its placeholder title. This is
/// also what CI uses to prove a booted simulator can run the app end to end
/// before it takes the screenshot artifact.
final class FotIACleanerUITests: XCTestCase {
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["FotIA Cleaner"].waitForExistence(timeout: 5))
    }
}
