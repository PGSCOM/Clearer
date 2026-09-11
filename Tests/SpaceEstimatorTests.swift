import Photos
import XCTest
@testable import Clearer

final class SpaceEstimatorTests: XCTestCase {
    func testLargerPhotosEstimateMoreBytes() {
        let small = SpaceEstimator.estimatedBytes(mediaType: .image, pixelWidth: 100, pixelHeight: 100, duration: 0)
        let large = SpaceEstimator.estimatedBytes(mediaType: .image, pixelWidth: 4000, pixelHeight: 3000, duration: 0)
        XCTAssertGreaterThan(large, small)
    }

    func testLongerVideosEstimateMoreBytes() {
        let short = SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 1920, pixelHeight: 1080, duration: 5)
        let long = SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 1920, pixelHeight: 1080, duration: 300)
        XCTAssertGreaterThan(long, short)
    }

    func testHigherResolutionVideosEstimateMoreBytes() {
        // A 4K video isn't the same size as a 720p one of the same
        // duration — resolution has to move the estimate, or sorting
        // videos "by occupancy" in VideoModeView would really just be
        // sorting by duration.
        let small = SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 1280, pixelHeight: 720, duration: 60)
        let large = SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 3840, pixelHeight: 2160, duration: 60)
        XCTAssertGreaterThan(large, small)
    }

    func testVideoWithUnknownDimensionsFallsBackToA1080pRate() {
        // Some third-party/shared-album videos report 0×0. Falling through
        // pow(0, …) = 0 would silently estimate 0 bytes and drop them to
        // the bottom of every size-sorted list.
        let unknownDimensions = SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 0, pixelHeight: 0, duration: 60)
        XCTAssertGreaterThan(unknownDimensions, 0)
    }

    func testZeroInputsEstimateZeroBytes() {
        XCTAssertEqual(SpaceEstimator.estimatedBytes(mediaType: .image, pixelWidth: 0, pixelHeight: 0, duration: 0), 0)
        XCTAssertEqual(SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 1920, pixelHeight: 1080, duration: 0), 0)
    }

    // MARK: - totalEstimatedBytes (batch, for TrashView)

    func testTotalEstimatedBytesSumsEachInput() {
        let inputs = [
            AssetSizeInput(mediaType: .image, pixelWidth: 100, pixelHeight: 100, duration: 0),
            AssetSizeInput(mediaType: .image, pixelWidth: 100, pixelHeight: 100, duration: 0),
        ]
        let single = SpaceEstimator.estimatedBytes(mediaType: .image, pixelWidth: 100, pixelHeight: 100, duration: 0)
        XCTAssertEqual(SpaceEstimator.totalEstimatedBytes(for: inputs), single * 2)
    }

    func testTotalEstimatedBytesOfEmptyListIsZero() {
        XCTAssertEqual(SpaceEstimator.totalEstimatedBytes(for: []), 0)
    }
}
