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

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        preloadCachedScores()
    }

    private func preloadCachedScores() {
        let cached = (try? modelContext.fetch(FetchDescriptor<AssetAnalysis>())) ?? []
        for entry in cached {
            scores[entry.assetID] = (entry.overallScore, entry.isUtility)
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
}
