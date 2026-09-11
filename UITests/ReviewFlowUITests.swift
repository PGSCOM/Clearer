import XCTest

/// End-to-end pass through the whole review flow, gated behind CI's
/// `review_ui_test` workflow_dispatch input (off by default — see
/// `.github/workflows/ci.yml`) because it needs photo access granted
/// non-interactively and fixture media seeded ahead of launch, which the
/// default onboarding smoke test deliberately avoids.
///
/// Relies on `.github/workflows/ci.yml` having already, before this test
/// runs: granted Photos access via `simctl privacy grant photos`, and
/// seeded `Tests/Fixtures/long-video.mp4` (200s) plus three JPEGs via
/// `simctl addmedia`. With every criterion except "Vídeos largos" turned
/// off, the video is the only thing the queue can ever contain — that's
/// what lets this test assert on an exact count of 1 without depending on
/// Vision's aesthetics scoring behaving identically in the simulator.
final class ReviewFlowUITests: XCTestCase {
    func testReviewDownloadZoomKeepUndoDeleteFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()

        // Access already granted by CI before launch, so the grid loads
        // straight away instead of showing onboarding.
        XCTAssertTrue(app.navigationBars["Fotos"].waitForExistence(timeout: 10))

        app.buttons["openAnalysis"].tap()
        XCTAssertTrue(app.navigationBars["Análisis"].waitForExistence(timeout: 5))

        // Only "Vídeos largos" stays on — the queue is then guaranteed to
        // be exactly the one seeded long video, regardless of what Vision
        // makes of the three seeded photos.
        for label in ["Capturas de pantalla", "Recibos y documentos", "Fotos de baja calidad", "Ráfagas (quedarse la mejor)"] {
            let toggle = app.switches[label]
            if toggle.waitForExistence(timeout: 5), toggle.value as? String == "1" {
                toggle.tap()
            }
        }

        app.buttons["Analizar fototeca"].tap()
        let reviewLink = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Revisar'")).firstMatch
        XCTAssertTrue(reviewLink.waitForExistence(timeout: 60), "analysis should finish and surface a review link")
        reviewLink.tap()

        XCTAssertTrue(app.navigationBars["Revisar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Vídeo largo"].waitForExistence(timeout: 10), "the one flagged item should be the long video")

        // Open the full-screen viewer, confirm the download control is
        // there, close without downloading (no iCloud in the simulator).
        app.descendants(matching: .any)["reviewPhoto"].tap()
        let downloadButton = app.buttons["Descargar original"]
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 5))
        app.buttons["closeViewer"].tap()
        XCTAssertTrue(app.navigationBars["Revisar"].waitForExistence(timeout: 5))

        // Keep, then undo — the card should come right back.
        app.buttons["Mantener"].tap()
        XCTAssertTrue(app.staticTexts["Has revisado todo"].waitForExistence(timeout: 5))
        app.buttons["Deshacer"].tap()
        XCTAssertTrue(app.staticTexts["Vídeo largo"].waitForExistence(timeout: 5))

        // This time, delete.
        app.buttons["Eliminar"].tap()
        XCTAssertTrue(app.staticTexts["Has revisado todo"].waitForExistence(timeout: 5))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ir a la papelera'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Papelera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Espacio estimado"].waitForExistence(timeout: 5))
    }
}
