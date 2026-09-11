import AVFoundation
import Photos
import UIKit

/// The single gateway to PhotoKit for the whole app — fetching, thumbnails,
/// and deleting all live here, nowhere else. For the image-fetching APIs
/// specifically (`PHImageManager`, `PHCachingImageManager`,
/// `.requestImage(`) CI enforces this with a grep guard
/// (`.github/workflows/ci.yml`); the rest is enforced by convention, since
/// those calls don't carry the iCloud-download risk the guard exists for.
///
/// The rule that matters more than anything else in this app: nothing here
/// downloads a full-resolution original from iCloud AUTOMATICALLY — not the
/// analysis pass, not the grid, not prefetch. Network access for image
/// requests stays off everywhere except inside `originalImage(for:onProgress:)`,
/// the one method that exists specifically to do that download, and only
/// ever runs from an explicit user tap on "Download original" for one photo
/// at a time. CI greps for that one flag flipped on and fails the build if
/// it appears anywhere but there, or more than once — see `ci.yml` for the
/// exact pattern (not spelled out here, so this comment can't shadow-match
/// its own guard).
actor PhotoLibrary {
    static let shared = PhotoLibrary()

    private let imageManager = PHCachingImageManager()

    /// ponytail: one original download in flight at a time — a decoded
    /// original can be tens to ~190MB (ProRAW), so holding more than one
    /// isn't worth the memory. The UI only ever offers one at a time anyway.
    private var inFlightOriginalRequest: PHImageRequestID?

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

    /// Videos only, filtered at the PhotoKit level via the native
    /// `mediaType` fetch overload — for `VideoModeView`, which stands on
    /// its own without needing the "Analizar fototeca" pass (videos skip
    /// Vision entirely, see `AnalysisCoordinator.analyze`).
    func fetchAllVideos() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .video, options: options)
    }

    /// Looks up a single asset by the ID other layers hold instead of a
    /// live `PHAsset` (see `AssetSignals`'/`ReviewItem`'s doc comments for
    /// why). A metadata-only query — cheap, no image data involved.
    func asset(withID id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Batch version of `asset(withID:)`'s metadata read, for callers that
    /// need many assets at once (`estimatedFreedBytes` over the whole
    /// trash) — one `fetchAssets` call instead of one per ID. Returns a
    /// plain `Sendable` struct rather than `PHAsset` itself, which isn't
    /// `Sendable` and shouldn't cross the actor boundary.
    func sizeInputs(withIDs ids: [String]) -> [AssetSizeInput] {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var results: [AssetSizeInput] = []
        results.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            results.append(AssetSizeInput(
                mediaType: asset.mediaType,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration
            ))
        }
        return results
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

    // MARK: - Original download (the one deliberate exception)

    /// Downloads the full-resolution original from iCloud if needed. This is
    /// the ONLY place in the app where `isNetworkAccessAllowed` is `true` —
    /// see the type doc comment. Only ever called from an explicit user tap.
    ///
    /// `.highQualityFormat` (not `.opportunistic`) for the same reason
    /// `thumbnail(for:targetSize:)` picks `.fastFormat`: it's the delivery
    /// mode PhotoKit guarantees calls the result handler exactly once, so
    /// the continuation can't be left hanging.
    func originalImage(for asset: PHAsset, onProgress: @escaping @Sendable (Double) -> Void) async -> OriginalImageResult {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isSynchronous = false
            options.progressHandler = { progress, _, _, _ in
                onProgress(progress)
            }

            inFlightOriginalRequest = imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { [weak self] image, info in
                Task { await self?.clearInFlightRequest() }
                let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                if wasCancelled {
                    continuation.resume(returning: .cancelled)
                } else if let image {
                    continuation.resume(returning: .image(image))
                } else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(returning: .failed(error?.localizedDescription ?? "unknown error"))
                }
            }
        }
    }

    /// Cancels the one original download that may be in flight. PhotoKit
    /// still calls the result handler with `PHImageCancelledKey` after this,
    /// so `originalImage`'s continuation always resolves — nothing leaks.
    func cancelOriginalDownload() {
        guard let requestID = inFlightOriginalRequest else { return }
        imageManager.cancelImageRequest(requestID)
    }

    private func clearInFlightRequest() {
        inFlightOriginalRequest = nil
    }

    // MARK: - Video track access (for on-device recoding)

    /// Hands back the underlying `AVAsset` so `VideoRecoder` can read its
    /// frames. Same iCloud rule as everywhere else: network access stays
    /// off, so an asset that isn't fully on-device comes back `nil` instead
    /// of triggering a download.
    func avAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    /// The video's real on-disk byte size — the public, documented
    /// equivalent of the undocumented `fileSize` KVC key this app
    /// deliberately avoids (see `SpaceEstimator`'s doc comment): once we
    /// have the `AVAsset`, its backing file's `URLResourceValues` carries
    /// an exact size, no network, no private API. `nil` if the video is
    /// iCloud-only (same rule as `avAsset(for:)`) or if PhotoKit hands back
    /// a composition instead of a single file — an edited or slow-motion
    /// video, which has no one "file size" to read this way.
    func videoFileSize(for asset: PHAsset) async -> Int64? {
        guard let avAsset = await avAsset(for: asset), let urlAsset = avAsset as? AVURLAsset else {
            return nil
        }
        guard let values = try? urlAsset.url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    // MARK: - Saving a recoded video

    /// Adds a recoded video file as a brand-new asset — it does not touch
    /// the original. Callers stage the original for deletion themselves
    /// (`AnalysisCoordinator.markForDeletion`) once this succeeds, reusing
    /// the existing trash/review flow instead of a separate one. Returns
    /// the new asset's local identifier.
    func addVideoAsset(fileURL: URL) async throws -> String {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: fileURL, options: nil)
            placeholder = request.placeholderForCreatedAsset
        }
        guard let id = placeholder?.localIdentifier else {
            throw SaveVideoError.missingPlaceholder
        }
        return id
    }

    // MARK: - Deleting

    /// Deletes assets by ID. iOS shows its own native confirmation alert
    /// for this — that's inherent to `PHAssetChangeRequest.deleteAssets`,
    /// not something we trigger or could bypass — and deleted assets still
    /// land in Photos' own "Recently Deleted" for 30 days on top of
    /// whatever staging the app itself does.
    ///
    /// Fetches the assets INSIDE the change block (not from a
    /// `PHFetchResult` captured from outside) — the documented-safe
    /// pattern for this call, and it avoids carrying a non-`Sendable`
    /// PhotoKit type across the actor boundary.
    ///
    /// Callers should race this against a timeout (`withTimeout`) —
    /// `performChanges`'s completion has a confirmed, if rare, failure
    /// mode on some iOS 26 builds where it never fires at all.
    func deleteAssets(withIDs ids: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }
}

enum ThumbnailResult {
    case available(UIImage)
    case iCloudOnly
    case unavailable
}

enum OriginalImageResult {
    case image(UIImage)
    case cancelled
    case failed(String)
}

enum SaveVideoError: Error {
    case missingPlaceholder
}

/// The subset of `PHAsset` metadata `SpaceEstimator` needs — a `Sendable`
/// DTO so it can cross the `PhotoLibrary` actor boundary, same reasoning as
/// `AssetSignals` in `Detectors.swift`.
struct AssetSizeInput: Sendable {
    let mediaType: PHAssetMediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
}
