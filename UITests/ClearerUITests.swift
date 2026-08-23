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
        // Force the locale instead of asserting on whatever the runner's
        // simulator defaults to. Bit us for real once already: adding the
        // English translation for "Continuar" made this test start failing
        // on CI, not because anything broke, but because the app was now
        // correctly showing "Continue" — the simulator's default language
        // is English, and the localization catalog started actually being
        // applied. Pinning to Spanish (the source language, our primary
        // market) makes the test deterministic regardless of runner
        // defaults, and still exercises real localized string lookup.
        app.launchArguments += ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Clearer"].waitForExistence(timeout: 5))
        // `.exists` alone doesn't wait/retry — checking it right after a
        // `waitForExistence` succeeded elsewhere isn't a guarantee this
        // other element has finished laying out too.
        XCTAssertTrue(app.buttons["Continuar"].waitForExistence(timeout: 5))
    }
}
