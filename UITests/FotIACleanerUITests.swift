import XCTest

/// Smoke test: on a fresh install (photo access not yet determined — the
/// state every CI simulator starts in) the app shows the permission gate,
/// not a crash and not a blank screen. Deliberately doesn't tap "Dar
/// acceso" — that would trigger the real system permission alert, which
/// isn't worth wrangling in CI for a Fase 1 smoke test.
final class FotIACleanerUITests: XCTestCase {
    func testShowsPhotoAccessGateOnFirstLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Dar acceso"].waitForExistence(timeout: 5))
    }
}
