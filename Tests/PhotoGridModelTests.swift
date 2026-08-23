import XCTest
import UIKit
@testable import Clearer

/// `PhotoGridModel.noteThumbnailResult` takes a plain asset ID instead of a
/// `PHAsset` specifically so this is testable without a live photo library
/// (`PHAsset` has no public initializer — you can only get one from a real
/// fetch).
@MainActor
final class PhotoGridModelTests: XCTestCase {
    func testCountsEachICloudOnlyAssetExactlyOnce() {
        let model = PhotoGridModel()

        model.noteThumbnailResult(.iCloudOnly, assetID: "a")
        model.noteThumbnailResult(.iCloudOnly, assetID: "a") // duplicate delivery, same asset
        model.noteThumbnailResult(.iCloudOnly, assetID: "b")
        model.noteThumbnailResult(.available(UIImage()), assetID: "c") // not iCloud-only
        model.noteThumbnailResult(.unavailable, assetID: "d") // not iCloud-only

        XCTAssertEqual(model.iCloudOnlyCount, 2)
    }
}
