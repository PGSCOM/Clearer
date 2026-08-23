import Photos
import XCTest
@testable import FotIACleaner

final class DetectorsTests: XCTestCase {
    private func signals(
        mediaType: PHAssetMediaType = .image,
        isScreenshot: Bool = false,
        isLivePhoto: Bool = false,
        burstIdentifier: String? = nil,
        duration: TimeInterval = 0,
        overallScore: Float? = nil,
        isUtility: Bool? = nil
    ) -> AssetSignals {
        AssetSignals(
            mediaType: mediaType,
            isScreenshot: isScreenshot,
            isLivePhoto: isLivePhoto,
            burstIdentifier: burstIdentifier,
            duration: duration,
            overallScore: overallScore,
            isUtility: isUtility
        )
    }

    // MARK: - Per-criterion flagging

    func testFlagsScreenshotWhenEnabled() {
        let reasons = Detectors.reasons(for: signals(isScreenshot: true), criteria: CleanupCriteria())
        XCTAssertTrue(reasons.contains(.screenshot))
    }

    func testDoesNotFlagScreenshotWhenDisabled() {
        var criteria = CleanupCriteria()
        criteria.flagScreenshots = false
        let reasons = Detectors.reasons(for: signals(isScreenshot: true), criteria: criteria)
        XCTAssertFalse(reasons.contains(.screenshot))
    }

    func testFlagsUtilityOnlyWhenAnalyzedAndTrue() {
        let notYetAnalyzed = Detectors.reasons(for: signals(isUtility: nil), criteria: CleanupCriteria())
        XCTAssertFalse(notYetAnalyzed.contains(.utility))

        let analyzedNotUtility = Detectors.reasons(for: signals(isUtility: false), criteria: CleanupCriteria())
        XCTAssertFalse(analyzedNotUtility.contains(.utility))

        let analyzedUtility = Detectors.reasons(for: signals(isUtility: true), criteria: CleanupCriteria())
        XCTAssertTrue(analyzedUtility.contains(.utility))
    }

    func testLowQualityThresholdIsExclusiveAtTheBoundary() {
        var criteria = CleanupCriteria()
        criteria.lowQualityThreshold = -0.3

        let atBoundary = Detectors.reasons(for: signals(overallScore: -0.3), criteria: criteria)
        XCTAssertFalse(atBoundary.contains(.lowQuality), "score == threshold should not flag")

        let belowBoundary = Detectors.reasons(for: signals(overallScore: -0.31), criteria: criteria)
        XCTAssertTrue(belowBoundary.contains(.lowQuality))

        let notYetAnalyzed = Detectors.reasons(for: signals(overallScore: nil), criteria: criteria)
        XCTAssertFalse(notYetAnalyzed.contains(.lowQuality))
    }

    func testLongVideoRequiresVideoMediaTypeAndDuration() {
        var criteria = CleanupCriteria()
        criteria.longVideoThreshold = 180

        let longVideo = Detectors.reasons(for: signals(mediaType: .video, duration: 200), criteria: criteria)
        XCTAssertTrue(longVideo.contains(.longVideo))

        let shortVideo = Detectors.reasons(for: signals(mediaType: .video, duration: 60), criteria: criteria)
        XCTAssertFalse(shortVideo.contains(.longVideo))

        let longButNotVideo = Detectors.reasons(for: signals(mediaType: .image, duration: 200), criteria: criteria)
        XCTAssertFalse(longButNotVideo.contains(.longVideo), "duration on a still image should never flag longVideo")
    }

    func testMultipleReasonsCanApplyAtOnce() {
        let reasons = Detectors.reasons(
            for: signals(isScreenshot: true, overallScore: -0.9, isUtility: true),
            criteria: CleanupCriteria()
        )
        XCTAssertEqual(reasons, [.screenshot, .utility, .lowQuality])
    }

    func testNoCriteriaEnabledFlagsNothing() {
        let criteria = CleanupCriteria(
            flagScreenshots: false,
            flagUtility: false,
            flagLowQuality: false,
            flagLongVideos: false,
            flagBurstDuplicates: false
        )
        let reasons = Detectors.reasons(
            for: signals(mediaType: .video, isScreenshot: true, duration: 999, overallScore: -1, isUtility: true),
            criteria: criteria
        )
        XCTAssertTrue(reasons.isEmpty)
    }

    // MARK: - Burst duplicates

    func testSingleAssetBurstHasNoDuplicates() {
        let result = Detectors.excessIDs(in: [(id: "a", overallScore: 0.5)])
        XCTAssertTrue(result.isEmpty)
    }

    func testBurstKeepsHighestScoringAsset() {
        let result = Detectors.excessIDs(in: [
            (id: "a", overallScore: 0.2),
            (id: "b", overallScore: 0.9),
            (id: "c", overallScore: 0.5),
        ])
        XCTAssertEqual(result, ["a", "c"])
    }

    func testBurstTieKeepsTheFirstOccurrence() {
        let result = Detectors.excessIDs(in: [
            (id: "a", overallScore: 0.5),
            (id: "b", overallScore: 0.5),
        ])
        XCTAssertEqual(result, ["b"], "a came first with the same score, so a should be kept")
    }

    func testBurstTreatsMissingScoreAsLowestPriority() {
        let result = Detectors.excessIDs(in: [
            (id: "a", overallScore: nil),
            (id: "b", overallScore: 0.1),
        ])
        XCTAssertEqual(result, ["a"])
    }
}
