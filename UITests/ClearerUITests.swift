import XCTest

/// Smoke test: on a fresh install (photo access not yet determined — the
/// state every CI simulator starts in) the app shows onboarding's welcome
/// step, not a crash and not a blank screen. Deliberately doesn't tap
/// through to the privacy step / "Dar acceso a mis fotos" — that would
/// trigger the real system permission alert, which isn't worth wrangling
/// in CI for a smoke test.
final class ClearerUITests: XCTestCase {
    func testShowsOnboardingOnFirstLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Clearer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continuar"].exists)
    }
}
