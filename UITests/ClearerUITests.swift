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
        // `.exists` alone doesn't wait/retry — checking it right after a
        // `waitForExistence` succeeded elsewhere isn't a guarantee this
        // other element has finished laying out too (bit us once already:
        // TabView's UIKit-backed paging seems to settle its chrome a beat
        // after the current page's own content is already queryable).
        XCTAssertTrue(app.buttons["Continuar"].waitForExistence(timeout: 5))
    }
}
