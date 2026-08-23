import Photos
import UIKit

/// The ONLY file in this project allowed to touch PhotoKit's image-fetching
/// APIs (`PHImageManager`, `PHCachingImageManager`, `.requestImage(`). CI
/// enforces this with a grep guard (`.github/workflows/ci.yml`) — if you
/// need a thumbnail or a photo list anywhere else, call through this actor,
/// don't reach for PhotoKit directly.
///
/// The one rule that matters more than anything else in this app:
/// `isNetworkAccessAllowed` is ALWAYS false here. That's what guarantees we
/// never pull a full-resolution original down from iCloud just to look at
/// it — the entire reason this app exists.
actor PhotoLibrary {
    static let shared = PhotoLibrary()

    private let imageManager = PHCachingImageManager()

    private init() {}

    // MARK: - Permission

    /// Safe to call synchronously — it only reads cached system state, it
    /// never prompts.
    nonisolated func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// `.readWrite` because Fase 3 needs to delete photos later; asking
    /// once up front is simpler than stepping up permissions mid-flow.
    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: - Fetching

    /// Images AND videos — Fase 2's "vídeo largo" and "Live Photo" criteria
    /// need videos in the fetch, not just stills. `PHFetchResult` is a
    /// lazy, index-backed view over the Photos database — cheap to grab in
    /// full even for huge libraries, since individual `PHAsset`s only get
    /// hydrated when actually accessed.
    func fetchAllAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: options)
    }

    // MARK: - Thumbnails

    /// Fetches the best thumbnail already available on-device. Never
    /// touches the network: an asset that only lives in iCloud comes back
    /// as `.iCloudOnly`, never downloaded.
    ///
    /// `deliveryMode = .fastFormat` is deliberate, not just "fast": it's
    /// the one mode PhotoKit guarantees calls the result handler exactly
    /// once. `.opportunistic` can call back twice (a quick pass, then a
    /// better one) — but the "better" pass may need network, which we've
    /// disallowed, and there's no documented guarantee it still fires a
    /// final callback in that case. Rather than risk a permanently
    /// suspended continuation, take the one guaranteed answer.
    func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> ThumbnailResult {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false

            // ponytail: no cancellation wiring (PHImageCancelledKey /
            // imageManager.cancelImageRequest) — SwiftUI's `.task` on each
            // grid cell already cancels the *awaiting* task when a cell is
            // recycled, so nothing acts on a stale result. The underlying
            // PhotoKit request still runs to completion either way; add
            // real cancellation if scrolling perf on huge libraries
            // becomes a measured problem.
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let image {
                    continuation.resume(returning: .available(image))
                } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                    continuation.resume(returning: .iCloudOnly)
                } else {
                    continuation.resume(returning: .unavailable)
                }
            }
        }
    }
}

enum ThumbnailResult {
    case available(UIImage)
    case iCloudOnly
    case unavailable
}
