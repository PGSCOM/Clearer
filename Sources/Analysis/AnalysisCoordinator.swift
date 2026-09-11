import AVFoundation
import Observation
import Photos
import SwiftData
import Vision

/// Walks the fetched library, running Vision on whatever isn't already
/// cached in SwiftData, and reports progress for a UI progress bar.
///
/// Feature prints live only in `featurePrints` (in memory, this session)
/// rather than persisted alongside `AssetAnalysis` in SwiftData.
///
/// ponytail: persisting them would mean archiving
/// `VNFeaturePrintObservation` via `NSSecureCoding` — plausible (Vision
/// observations generally conform), but not confirmed with enough
/// confidence to bet on blind, and the failure mode of getting it wrong
/// would be silent (a cache that never populates), not a crash. Recomputing
/// feature prints once per session is the safe trade: the aesthetics score
/// (the actually-expensive Vision pass) still gets cached properly. Revisit
/// if relaunch-to-regroup speed on a huge library becomes a real complaint.
@Observable
@MainActor
final class AnalysisCoordinator {
    private(set) var isAnalyzing = false
    private(set) var analyzedCount = 0
    private(set) var totalCount = 0

    /// assetID -> cached Vision aesthetics result, backed by SwiftData.
    private(set) var scores: [String: (overallScore: Float, isUtility: Bool)] = [:]
    /// assetID -> feature print, in-memory only, this session.
    private(set) var featurePrints: [String: VNFeaturePrintObservation] = [:]

    /// The app's own trash: assets the user marked for deletion during
    /// review, staged here until `TrashView` commits them. Separate from
    /// (and in addition to) Photos' own 30-day "Recently Deleted" — this
    /// is the chance to change your mind BEFORE anything actually happens.
    private(set) var pendingDeletionIDs: Set<String> = []

    /// Which flagged assets the user has already decided on — the single
    /// source of truth behind `ReviewView`'s one-at-a-time queue AND
    /// `PhotoGalleryView`'s tap-to-mark grid, so a photo decided in one
    /// doesn't linger as "still pending" in the other. Backed by
    /// `ReviewProgressStore`; see `markReviewed`/`unmarkReviewed`.
    private(set) var reviewedIDs: Set<String> = []

    /// assetID -> real on-disk byte size, backed by SwiftData. `-1` means
    /// "measured, no real size available" (see `VideoSizeRecord`).
    private(set) var videoSizes: [String: Int64] = [:]
    private(set) var isMeasuringVideoSizes = false
    private(set) var measuredVideoCount = 0
    private(set) var totalVideoCount = 0

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        preloadCachedScores()
        preloadCachedVideoSizes()
        reviewedIDs = ReviewProgressStore.load(from: modelContext)
    }

    private func preloadCachedScores() {
        let cached = (try? modelContext.fetch(FetchDescriptor<AssetAnalysis>())) ?? []
        for entry in cached {
            scores[entry.assetID] = (entry.overallScore, entry.isUtility)
        }
    }

    private func preloadCachedVideoSizes() {
        let cached = (try? modelContext.fetch(FetchDescriptor<VideoSizeRecord>())) ?? []
        for entry in cached {
            videoSizes[entry.assetID] = entry.byteSize
        }
    }

    /// Analyzes every still-image asset not already in `scores`. Videos are
    /// skipped here — their only Vision-independent criterion (long video)
    /// is read straight off `PHAsset.duration` wherever results are
    /// computed, no analysis pass needed.
    func analyze(_ fetchResult: PHFetchResult<PHAsset>, targetSize: CGSize = CGSize(width: 512, height: 512)) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        totalCount = fetchResult.count
        analyzedCount = 0

        for index in 0..<fetchResult.count {
            if Task.isCancelled { break }
            let asset = fetchResult.object(at: index)
            defer { analyzedCount += 1 }

            guard asset.mediaType == .image, scores[asset.localIdentifier] == nil else { continue }

            let thumbnailResult = await PhotoLibrary.shared.thumbnail(for: asset, targetSize: targetSize)
            guard case .available(let image) = thumbnailResult,
                  let result = await VisionAnalyzer.analyze(image) else { continue }

            let assetID = asset.localIdentifier
            scores[assetID] = (result.overallScore, result.isUtility)
            if let featurePrint = result.featurePrint {
                featurePrints[assetID] = featurePrint
            }
            modelContext.insert(
                AssetAnalysis(assetID: assetID, overallScore: result.overallScore, isUtility: result.isUtility)
            )

            if analyzedCount % 25 == 0 {
                try? modelContext.save() // periodic, so a killed app doesn't lose a whole scan
            }
        }

        try? modelContext.save()
    }

    /// Distance between two already-analyzed assets' feature prints.
    /// `Float.greatestFiniteMagnitude` (never groups) if either is missing
    /// or Vision couldn't compute a distance between them.
    func featurePrintDistance(_ lhs: String, _ rhs: String) -> Float {
        guard let a = featurePrints[lhs], let b = featurePrints[rhs] else {
            return .greatestFiniteMagnitude
        }
        var distance: Float = .greatestFiniteMagnitude
        try? a.computeDistance(&distance, to: b)
        return distance
    }

    // MARK: - Video size measurement

    /// Real byte size for every video in `fetchResult` not already in
    /// `videoSizes` — `VideoModeView`'s "sort by occupancy" only means
    /// anything once this has run. Same shape as `analyze()`: skip what's
    /// cached, measure, save periodically so a killed app doesn't lose a
    /// whole pass. `PhotoLibrary.videoFileSize(for:)` already refuses
    /// iCloud-only videos (returns `nil`, stored here as `-1`) — nothing
    /// here downloads anything.
    func measureVideoSizes(_ fetchResult: PHFetchResult<PHAsset>) async {
        guard !isMeasuringVideoSizes else { return }
        isMeasuringVideoSizes = true
        defer { isMeasuringVideoSizes = false }

        totalVideoCount = fetchResult.count
        measuredVideoCount = 0

        for index in 0..<fetchResult.count {
            if Task.isCancelled { break }
            let asset = fetchResult.object(at: index)
            defer { measuredVideoCount += 1 }

            guard videoSizes[asset.localIdentifier] == nil else { continue }

            let assetID = asset.localIdentifier
            let size = await PhotoLibrary.shared.videoFileSize(for: asset) ?? -1
            videoSizes[assetID] = size
            modelContext.insert(VideoSizeRecord(assetID: assetID, byteSize: size))

            if measuredVideoCount % 25 == 0 {
                try? modelContext.save()
            }
        }

        try? modelContext.save()
    }

    // MARK: - Video recoding

    /// Recodes one video to a smaller resolution (bitrate and color space
    /// preserved — see `VideoRecoder`), saves the result as a new asset, and
    /// stages the original for deletion through the same trash flow as
    /// every other cleanup decision. Returns the new asset's ID on success.
    func recodeVideo(
        id: String,
        to target: VideoRecoder.Target,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        guard let phAsset = await PhotoLibrary.shared.asset(withID: id) else {
            throw RecodeVideoError.assetNotFound
        }
        guard let avAsset = await PhotoLibrary.shared.avAsset(for: phAsset) else {
            throw RecodeVideoError.iCloudOnly
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await VideoRecoder.recode(avAsset, to: target, outputURL: outputURL, onProgress: onProgress)
        let newID = try await PhotoLibrary.shared.addVideoAsset(fileURL: outputURL)
        markForDeletion(id)
        // In case this video also matched "vídeos largos": it shouldn't
        // still show up as pending in ReviewView once it's already staged
        // for deletion here.
        markReviewed(id)
        return newID
    }

    // MARK: - Trash staging

    func markForDeletion(_ id: String) {
        pendingDeletionIDs.insert(id)
    }

    func unmarkForDeletion(_ id: String) {
        pendingDeletionIDs.remove(id)
    }

    // MARK: - Review progress

    /// Called on every "Mantener"/"Eliminar" decision, whether it comes
    /// from `ReviewView`'s one-at-a-time queue or a tap in
    /// `PhotoGalleryView`'s grid — both read `reviewedIDs` from here, so
    /// neither can strand a photo the other already decided on. Saves
    /// immediately rather than batching: this fires on individual taps, not
    /// in a tight loop like `analyze()`. ponytail: `ReviewProgressStore.save`
    /// rewrites the whole set as an array — O(reviewedIDs.count) per tap.
    /// Fine at review-session scale; if it's ever felt at ~10k decisions,
    /// batch or debounce the save instead of writing on every call.
    func markReviewed(_ id: String) {
        guard reviewedIDs.insert(id).inserted else { return }
        ReviewProgressStore.save(reviewedIDs, to: modelContext)
    }

    func unmarkReviewed(_ id: String) {
        guard reviewedIDs.remove(id) != nil else { return }
        ReviewProgressStore.save(reviewedIDs, to: modelContext)
    }

    /// Rough "space freed" figure for the pending trash — see
    /// `SpaceEstimator` for why this is an estimate, not an exact figure.
    /// One batch `PhotoLibrary` fetch, not one PhotoKit round-trip per
    /// pending ID: with thousands marked for deletion, `TrashView`'s
    /// `.task(id: pendingDeletionIDs)` re-runs this on every change, and a
    /// per-ID fetch there would visibly stall as the trash grows.
    func estimatedFreedBytes() async -> Int64 {
        let inputs = await PhotoLibrary.shared.sizeInputs(withIDs: Array(pendingDeletionIDs))
        return SpaceEstimator.totalEstimatedBytes(for: inputs)
    }

    /// Called after a successful delete: drops the given IDs from every
    /// piece of in-memory and persisted state that still references them —
    /// they're gone, there's nothing left to cache.
    func clearDeleted(_ ids: [String]) {
        let idSet = Set(ids)
        for id in ids {
            pendingDeletionIDs.remove(id)
            scores.removeValue(forKey: id)
            featurePrints.removeValue(forKey: id)
            videoSizes.removeValue(forKey: id)
        }
        if let cached = try? modelContext.fetch(FetchDescriptor<AssetAnalysis>()) {
            for record in cached where idSet.contains(record.assetID) {
                modelContext.delete(record)
            }
        }
        if let cachedSizes = try? modelContext.fetch(FetchDescriptor<VideoSizeRecord>()) {
            for record in cachedSizes where idSet.contains(record.assetID) {
                modelContext.delete(record)
            }
        }
        try? modelContext.save()
    }
}

enum RecodeVideoError: Error {
    case assetNotFound
    case iCloudOnly
}

extension RecodeVideoError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .assetNotFound: "No se encontró el vídeo."
        case .iCloudOnly: "Este vídeo solo está en iCloud: descárgalo antes de recodificarlo."
        }
    }
}
