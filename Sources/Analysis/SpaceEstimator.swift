import Foundation
import Photos

/// Rough on-disk size estimate from public `PHAsset` properties only —
/// pixel dimensions and duration, never the file itself. There's no public
/// API for an asset's real byte size that doesn't either require
/// downloading the resource (defeats the whole point of this app) or lean
/// on an undocumented KVC key (`value(forKey: "fileSize")` — real, widely
/// used, but Apple explicitly doesn't guarantee it and it's a plausible
/// App Review flag). Good enough for "you freed about this much", labelled
/// as an estimate in the UI — not for anything that needs to be exact. For
/// video specifically, this also backs `VideoModeView`'s sort order until
/// (or unless) `AnalysisCoordinator.measureVideoSizes` has a real byte count
/// for that asset — see `PhotoLibrary.videoFileSize(for:)`.
enum SpaceEstimator {
    static func estimatedBytes(mediaType: PHAssetMediaType, pixelWidth: Int, pixelHeight: Int, duration: TimeInterval) -> Int64 {
        switch mediaType {
        case .video:
            // Bitrate scaled by resolution, calibrated against Apple's own
            // published HEVC/30fps figures (Settings > Camera > Record
            // Video): 720p ≈ 40 MB/min, 1080p ≈ 60 MB/min (= 8 Mbps
            // exactly), 4K ≈ 170 MB/min. A codec's bitrate scales
            // sublinearly with pixel count, not linearly — a flat
            // per-pixel rate overshoots 4K by ~40% and undershoots 720p by
            // ~30%; the 0.65 exponent below fits all three anchors within
            // ~13%. ponytail: assumes 30fps and says nothing about codec —
            // neither is public on `PHAsset`. Getting closer would mean
            // reading the real `AVAsset` per video, which is exactly the
            // cost this fallback exists to avoid.
            let pixelCount = Double(pixelWidth * pixelHeight)
            let referencePixels = 1920.0 * 1080.0
            let referenceBitsPerSecond = 8_000_000.0
            let ratio = pixelCount > 0 ? pow(pixelCount / referencePixels, 0.65) : 1.0
            let bitsPerSecond = referenceBitsPerSecond * ratio
            return Int64(duration * bitsPerSecond / 8)
        default:
            let bytesPerPixel = 0.8 // typical HEIC/JPEG compression at normal quality
            return Int64(Double(pixelWidth * pixelHeight) * bytesPerPixel)
        }
    }

    /// Sum of `estimatedBytes` over a whole trash's worth of assets —
    /// `AnalysisCoordinator.estimatedFreedBytes` is just this plus the
    /// PhotoKit batch fetch that produces `inputs`.
    static func totalEstimatedBytes(for inputs: [AssetSizeInput]) -> Int64 {
        inputs.reduce(into: 0) { total, input in
            total += estimatedBytes(
                mediaType: input.mediaType,
                pixelWidth: input.pixelWidth,
                pixelHeight: input.pixelHeight,
                duration: input.duration
            )
        }
    }
}
