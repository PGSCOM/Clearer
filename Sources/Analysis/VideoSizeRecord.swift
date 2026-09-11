import Foundation
import SwiftData

/// Caches the real on-disk byte size of a video, keyed by
/// `PHAsset.localIdentifier` — same shape as `AssetAnalysis`, but for
/// `PhotoLibrary.videoFileSize(for:)` instead of a Vision pass. `byteSize`
/// is `-1` for a video PhotoKit measured but couldn't get a real size for
/// (an edited/slow-mo asset that comes back as an `AVComposition`, not a
/// single `AVURLAsset`) — a sentinel, not a missing row, so
/// `AnalysisCoordinator.measureVideoSizes` doesn't keep retrying it on
/// every visit to the Vídeos tab.
@Model
final class VideoSizeRecord {
    @Attribute(.unique) var assetID: String
    var byteSize: Int64

    init(assetID: String, byteSize: Int64) {
        self.assetID = assetID
        self.byteSize = byteSize
    }
}
