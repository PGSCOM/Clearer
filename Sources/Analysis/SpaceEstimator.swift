import Photos

/// Rough on-disk size estimate from public `PHAsset` properties only —
/// pixel dimensions and duration, never the file itself. There's no public
/// API for an asset's real byte size that doesn't either require
/// downloading the resource (defeats the whole point of this app) or lean
/// on an undocumented KVC key (`value(forKey: "fileSize")` — real, widely
/// used, but Apple explicitly doesn't guarantee it and it's a plausible
/// App Review flag). Good enough for "you freed about this much", labelled
/// as an estimate in the UI — not for anything that needs to be exact.
enum SpaceEstimator {
    static func estimatedBytes(mediaType: PHAssetMediaType, pixelWidth: Int, pixelHeight: Int, duration: TimeInterval) -> Int64 {
        switch mediaType {
        case .video:
            let bitsPerSecond = 10_000_000.0 // ~10 Mbps, typical iPhone H.264/HEVC
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
