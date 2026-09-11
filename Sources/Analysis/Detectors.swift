import Photos

/// Plain metadata + (optional) cached Vision results for one asset. A DTO
/// on purpose, not a `PHAsset` — `PHAsset` has no public initializer, so
/// code that takes one directly can't be unit-tested without a live photo
/// library. `Detectors` never touches PhotoKit or Vision; it only reasons
/// about data someone else already fetched.
struct AssetSignals {
    let mediaType: PHAssetMediaType
    let isScreenshot: Bool
    let isLivePhoto: Bool
    let burstIdentifier: String?
    let duration: TimeInterval
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    /// nil until the Vision analysis pass has run for this asset.
    let overallScore: Float?
    /// nil until the Vision analysis pass has run for this asset.
    let isUtility: Bool?
}

enum CleanupReason: String, CaseIterable, Hashable {
    case screenshot
    case utility
    case lowQuality
    case longVideo
    case burstDuplicate
    case duplicate
}

/// What the user opted into during onboarding, plus the thresholds that
/// decide how aggressive each check is. Defaults are a starting point, not
/// tuned against a real library yet — expect to revisit once Pablo runs
/// this against his own photos.
struct CleanupCriteria: Equatable {
    var flagScreenshots = true
    var flagUtility = true
    var flagLowQuality = true
    var lowQualityThreshold: Float = -0.3
    var flagLongVideos = true
    var longVideoThreshold: TimeInterval = 180 // 3 minutes
    var flagBurstDuplicates = true
}

enum Detectors {
    /// Reasons that apply to a single asset in isolation. Burst duplicates
    /// and near-duplicates are group-level decisions — see `excessIDs`
    /// below and `Grouping`, respectively.
    static func reasons(for signals: AssetSignals, criteria: CleanupCriteria) -> Set<CleanupReason> {
        var reasons: Set<CleanupReason> = []

        if criteria.flagScreenshots, signals.isScreenshot {
            reasons.insert(.screenshot)
        }
        if criteria.flagUtility, signals.isUtility == true {
            reasons.insert(.utility)
        }
        if criteria.flagLowQuality, let score = signals.overallScore, score < criteria.lowQualityThreshold {
            reasons.insert(.lowQuality)
        }
        if criteria.flagLongVideos, signals.mediaType == .video, signals.duration >= criteria.longVideoThreshold {
            reasons.insert(.longVideo)
        }

        return reasons
    }

    /// Given a group of assets that are all "the same shot" — a camera
    /// burst OR a near-duplicate cluster from `Grouping`, same algorithm
    /// either way — returns the IDs that are NOT the best one (kept). Ties
    /// (equal or missing scores) keep whichever comes first in the input.
    static func excessIDs(in group: [(id: String, overallScore: Float?)]) -> Set<String> {
        guard group.count > 1 else { return [] }
        guard let best = group.max(by: { ($0.overallScore ?? -1) < ($1.overallScore ?? -1) }) else {
            return []
        }
        // `max(by:)` picks the LAST element on ties, but we want to keep
        // the FIRST — find the true first-occurring max explicitly.
        let bestScore = best.overallScore ?? -1
        guard let keptID = group.first(where: { ($0.overallScore ?? -1) == bestScore })?.id else {
            return []
        }
        return Set(group.filter { $0.id != keptID }.map(\.id))
    }

    /// 4K UHD is 3840 pixels on the long edge — orientation doesn't matter,
    /// a portrait 2160×3840 recording counts the same as landscape.
    static func isFourK(pixelWidth: Int, pixelHeight: Int) -> Bool {
        max(pixelWidth, pixelHeight) >= 3840
    }
}
