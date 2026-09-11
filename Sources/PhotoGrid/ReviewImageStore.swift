import Observation
import UIKit

/// Owns image state for the review screen: thumbnails kept warm for a small
/// window of upcoming (and just-undone) cards, so scrolling through
/// ~10,000 decisions doesn't mean a blank flash on every single one, plus
/// the one-at-a-time full-resolution original download triggered by an
/// explicit tap (the one deliberate exception to the app's never-download
/// rule — see `PhotoLibrary`). `@MainActor` because every property here
/// drives SwiftUI directly.
@Observable
@MainActor
final class ReviewImageStore {
    private(set) var thumbnails: [String: UIImage] = [:]
    private(set) var failedIDs: Set<String> = []

    private(set) var fullResImage: UIImage?
    private(set) var fullResID: String?
    private(set) var downloadState: DownloadState = .idle

    private var loadTasks: [String: Task<Void, Never>] = [:]
    private var downloadTask: Task<Void, Never>?
    private var downloadGeneration = 0

    enum DownloadState: Equatable {
        case idle
        case downloading(Double)
        case done
        case failed(String)
    }

    /// Which IDs are worth keeping a thumbnail warm for right now: the next
    /// `ahead` pending cards (so moving forward never shows a blank card)
    /// plus the last `behind` reviewed ones (so Undo shows its photo
    /// instantly instead of re-fetching). Pure and tested on its own — no
    /// PhotoKit involved — so the edge cases (empty pending, empty history,
    /// fewer items than the window) are covered without a live photo
    /// library.
    ///
    /// `nonisolated` on purpose: it touches no instance state, and without
    /// it the class's `@MainActor` isolation applies to static members too
    /// — which the plain (non-MainActor) test methods in
    /// `ReviewImageStoreTests` can't call synchronously.
    nonisolated static func keepWarmIDs(pending: [String], recentlyReviewed: [String], ahead: Int = 4, behind: Int = 1) -> Set<String> {
        Set(pending.prefix(ahead)).union(recentlyReviewed.suffix(behind))
    }

    /// Loads thumbnails for every ID in `keepIDs` that isn't already cached
    /// (or already known to fail), and drops everything else — the cache
    /// size is bounded by `keepIDs.count` regardless of how many of the
    /// ~10,000 photos have been reviewed already.
    func updateWindow(keepIDs: Set<String>, targetSize: CGSize) {
        for id in thumbnails.keys where !keepIDs.contains(id) {
            thumbnails.removeValue(forKey: id)
        }
        for id in loadTasks.keys where !keepIDs.contains(id) {
            loadTasks[id]?.cancel()
            loadTasks.removeValue(forKey: id)
        }
        for id in keepIDs where thumbnails[id] == nil && loadTasks[id] == nil && !failedIDs.contains(id) {
            loadTasks[id] = Task { [weak self] in
                await self?.loadThumbnail(id: id, targetSize: targetSize)
            }
        }
    }

    private func loadThumbnail(id: String, targetSize: CGSize) async {
        defer { loadTasks.removeValue(forKey: id) }
        guard let asset = await PhotoLibrary.shared.asset(withID: id) else {
            failedIDs.insert(id)
            return
        }
        if Task.isCancelled { return }
        let result = await PhotoLibrary.shared.thumbnail(for: asset, targetSize: targetSize)
        if Task.isCancelled { return }
        switch result {
        case .available(let image):
            thumbnails[id] = image
            failedIDs.remove(id)
        case .iCloudOnly, .unavailable:
            failedIDs.insert(id)
        }
    }

    /// Re-attempts a thumbnail that previously failed — an asset that's
    /// momentarily unreadable shouldn't be a permanent dead end in a queue
    /// of thousands.
    func retry(id: String, targetSize: CGSize) {
        failedIDs.remove(id)
        loadTasks[id]?.cancel()
        loadTasks[id] = Task { [weak self] in
            await self?.loadThumbnail(id: id, targetSize: targetSize)
        }
    }

    // MARK: - Original download

    func downloadOriginal(id: String) {
        if fullResID == id, downloadState == .done { return }
        if fullResID == id, case .downloading = downloadState { return }

        downloadGeneration += 1
        let generation = downloadGeneration
        downloadTask?.cancel()
        fullResID = id
        fullResImage = nil
        downloadState = .downloading(0)

        downloadTask = Task { [weak self] in
            guard let asset = await PhotoLibrary.shared.asset(withID: id) else {
                self?.applyDownloadFailure("not-found", generation: generation)
                return
            }
            let result = await PhotoLibrary.shared.originalImage(for: asset) { progress in
                Task { @MainActor [weak self] in
                    self?.applyDownloadProgress(progress, generation: generation)
                }
            }
            self?.applyDownloadResult(result, generation: generation)
        }
    }

    func cancelDownload() {
        downloadGeneration += 1
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .idle
        Task { await PhotoLibrary.shared.cancelOriginalDownload() }
    }

    /// Called whenever the current card changes — a downloaded original
    /// belongs to one photo only, never carried over to the next.
    func resetFullRes(for id: String?) {
        guard fullResID != id else { return }
        downloadGeneration += 1
        downloadTask?.cancel()
        downloadTask = nil
        fullResImage = nil
        fullResID = nil
        downloadState = .idle
    }

    private func applyDownloadProgress(_ progress: Double, generation: Int) {
        guard generation == downloadGeneration else { return }
        downloadState = .downloading(progress)
    }

    private func applyDownloadFailure(_ message: String, generation: Int) {
        guard generation == downloadGeneration else { return }
        downloadState = .failed(message)
    }

    private func applyDownloadResult(_ result: OriginalImageResult, generation: Int) {
        guard generation == downloadGeneration else { return }
        switch result {
        case .image(let image):
            fullResImage = image
            downloadState = .done
        case .cancelled:
            downloadState = .idle
        case .failed(let message):
            downloadState = .failed(message)
        }
        downloadTask = nil
    }
}
