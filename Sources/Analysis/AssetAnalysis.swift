import Foundation
import SwiftData

/// Caches the expensive-to-recompute part of analysis (Vision's aesthetics
/// pass) per asset, keyed by `PHAsset.localIdentifier`. Deliberately does
/// NOT cache metadata that's already free to read straight off a live
/// `PHAsset` (screenshot flag, burst id, duration, media type) — only what
/// actually costs a Vision inference to produce.
///
/// Feature prints (for duplicate grouping) are NOT persisted here — see
/// `AnalysisCoordinator`. They're kept in memory for the session only.
///
/// Never stores the image itself.
@Model
final class AssetAnalysis {
    @Attribute(.unique) var assetID: String
    var overallScore: Float
    var isUtility: Bool
    var analyzedAt: Date

    init(assetID: String, overallScore: Float, isUtility: Bool, analyzedAt: Date = .now) {
        self.assetID = assetID
        self.overallScore = overallScore
        self.isUtility = isUtility
        self.analyzedAt = analyzedAt
    }
}
