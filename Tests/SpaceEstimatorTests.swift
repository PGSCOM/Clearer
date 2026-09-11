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

    func testVideoEstimateIgnoresPixelDimensions() {
        // Deliberate: duration is a far more reliable video-size signal
        // than resolution (bitrate varies a lot more than pixel count).
        let small = SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 100, pixelHeight: 100, duration: 60)
        let large = SpaceEstimator.estimatedBytes(mediaType: .video, pixelWidth: 4000, pixelHeight: 3000, duration: 60)
        XCTAssertEqual(small, large)
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
