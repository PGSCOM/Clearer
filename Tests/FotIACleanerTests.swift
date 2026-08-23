import XCTest
@testable import FotIACleaner

/// Fase 0 has no real logic yet — this just proves the test target links
/// against the app module (@testable import) and CI's `xcodebuild test`
/// step actually exercises it. Later fases add real coverage here
/// (Detectors, Grouping, threshold calibration).
final class FotIACleanerTests: XCTestCase {
    func testAppInfoName() {
        XCTAssertEqual(AppInfo.name, "FotIA Cleaner")
    }
}
