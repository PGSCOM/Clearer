import Photos
import SwiftUI

/// Pick which criteria matter, run the analysis, see counts, then jump into
/// review. The actual reviewing/deleting lives in `ReviewView`/`TrashView`
/// — this screen is "how many, of what kind" plus the entry point into
/// "now do something about it."
struct AnalysisResultsView: View {
    let fetchResult: PHFetchResult<PHAsset>
    let coordinator: AnalysisCoordinator

    @State private var criteria = CleanupCriteria()
    @State private var duplicateThreshold: Float = 0.35
    @State private var counts: [CleanupReason: Int] = [:]
    @State private var duplicateGroupCount = 0
    @State private var hasAnalyzed = false

    // Every asset's signals, read off `PHAsset` exactly once when analysis
    // finishes — not on every criteria toggle or slider drag. At ~10,000
    // photos, touching every `PHAsset` on each toggle is the difference
    // between an instant switch and a visible stall; recomputing over this
    // plain-struct snapshot instead is effectively free.
    @State private var assetSnapshot: [(id: String, signals: AssetSignals)] = []

    // Raw data behind `counts`, kept around so the review queue can be
    // rebuilt without a second full pass over `fetchResult`.
    @State private var flaggedSingles: [(id: String, reasons: Set<CleanupReason>)] = []
    @State private var burstGroups: [[(id: String, overallScore: Float?)]] = []
    @State private var duplicateGroupsWithScores: [[(id: String, overallScore: Float?)]] = []
    @State private var reviewItems: [ReviewItem] = []

    var body: some View {
        List {
            Section {
                if coordinator.isAnalyzing {
                    ProgressView(
                        value: Double(coordinator.analyzedCount),
                        total: Double(max(coordinator.totalCount, 1))
                    ) {
                        Text("Analizando \(coordinator.analyzedCount) de \(coordinator.totalCount)")
                    }
                } else {
                    Button(hasAnalyzed ? "Volver a analizar" : "Analizar fototeca") {
                        runAnalysis()
                    }
                }
            }

            Section("Qué buscar") {
                Toggle("Capturas de pantalla", isOn: $criteria.flagScreenshots)
                Toggle("Recibos y documentos", isOn: $criteria.flagUtility)
                Toggle("Fotos de baja calidad", isOn: $criteria.flagLowQuality)
                Toggle("Vídeos largos", isOn: $criteria.flagLongVideos)
                Toggle("Ráfagas (quedarse la mejor)", isOn: $criteria.flagBurstDuplicates)
            }

            if hasAnalyzed {
                Section("Resultado") {
                    resultRow("Capturas de pantalla", counts[.screenshot])
                    resultRow("Recibos y documentos", counts[.utility])
                    resultRow("Fotos de baja calidad", counts[.lowQuality])
                    resultRow("Vídeos largos", counts[.longVideo])
                    resultRow("Ráfagas de sobra", counts[.burstDuplicate])
                }

                Section("Casi duplicadas") {
                    HStack {
                        Text("Grupos encontrados")
                        Spacer()
                        Text("\(duplicateGroupCount)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $duplicateThreshold, in: 0.1...0.6)
                    Text("Cuanto más alto el umbral, más fotos distintas se agrupan como si fueran la misma.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !reviewItems.isEmpty {
                    Section {
                        NavigationLink {
                            ReviewView(reviewItems: reviewItems, coordinator: coordinator)
                        } label: {
                            Text("Revisar \(reviewItems.count) fotos")
                        }
                    }
                } else if !coordinator.pendingDeletionIDs.isEmpty {
                    // Everything's been reviewed already, but the trash
                    // from a previous pass is still sitting there.
                    Section {
                        NavigationLink {
                            TrashView(coordinator: coordinator)
                        } label: {
                            Text("Papelera (\(coordinator.pendingDeletionIDs.count))")
                        }
                    }
                }
            }
        }
        .navigationTitle("Análisis")
        .onChange(of: criteria) { _, _ in recomputeCounts() }
        .onChange(of: duplicateThreshold) { _, _ in recomputeDuplicateGroups() }
    }

    private func resultRow(_ label: String, _ count: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count ?? 0)")
                .foregroundStyle(.secondary)
        }
    }

    private func runAnalysis() {
        Task {
            await coordinator.analyze(fetchResult)
            buildAssetSnapshot()
            hasAnalyzed = true
            recomputeCounts()
            recomputeDuplicateGroups()
        }
    }

    /// The one pass over live `PHAsset`s — reads exactly what `Detectors`
    /// needs plus the cached Vision result, in `fetchResult`'s creation-date
    /// order (which `recomputeDuplicateGroups` below relies on). Everything
    /// downstream of this (both toggles and the duplicate-threshold slider)
    /// works off the snapshot it produces, never touching `PHAsset` again
    /// until the next "Volver a analizar".
    private func buildAssetSnapshot() {
        var snapshot: [(id: String, signals: AssetSignals)] = []
        snapshot.reserveCapacity(fetchResult.count)
        for index in 0..<fetchResult.count {
            let asset = fetchResult.object(at: index)
            let cached = coordinator.scores[asset.localIdentifier]
            snapshot.append((asset.localIdentifier, AssetSignals(
                mediaType: asset.mediaType,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
                burstIdentifier: asset.burstIdentifier,
                duration: asset.duration,
                overallScore: cached?.overallScore,
                isUtility: cached?.isUtility
            )))
        }
        assetSnapshot = snapshot
    }

    /// Pure array/dictionary work over `assetSnapshot` — no PhotoKit or
    /// Vision I/O, no live `PHAsset` reads — so running this synchronously
    /// on every criteria toggle stays instant even at ~10,000 photos.
    private func recomputeCounts() {
        var tally: [CleanupReason: Int] = [:]
        var burstsByID: [String: [(id: String, overallScore: Float?)]] = [:]
        var singles: [(id: String, reasons: Set<CleanupReason>)] = []

        for (id, signals) in assetSnapshot {
            let reasons = Detectors.reasons(for: signals, criteria: criteria)
            for reason in reasons {
                tally[reason, default: 0] += 1
            }
            if !reasons.isEmpty {
                singles.append((id, reasons))
            }
            if let burstID = signals.burstIdentifier {
                burstsByID[burstID, default: []].append((id, signals.overallScore))
            }
        }

        var burstGroupsList: [[(id: String, overallScore: Float?)]] = []
        if criteria.flagBurstDuplicates {
            var burstDuplicateCount = 0
            for burst in burstsByID.values where burst.count > 1 {
                burstDuplicateCount += Detectors.excessIDs(in: burst).count
                burstGroupsList.append(burst)
            }
            tally[.burstDuplicate] = burstDuplicateCount
        }

        counts = tally
        flaggedSingles = singles
        burstGroups = burstGroupsList
        rebuildReviewQueue()
    }

    /// Only re-runs `Grouping`, not Vision — feature prints are already in
    /// memory and `assetSnapshot` is already in creation-date order, so
    /// dragging the slider is cheap and live with no `PHAsset` touches.
    private func recomputeDuplicateGroups() {
        let orderedIDs = assetSnapshot.compactMap { id, _ in
            coordinator.featurePrints[id] != nil ? id : nil
        }
        let groups = Grouping.groups(
            ids: orderedIDs,
            threshold: duplicateThreshold,
            distance: coordinator.featurePrintDistance
        )
        duplicateGroupCount = groups.count
        duplicateGroupsWithScores = groups.map { group in
            group.map { (id: $0, overallScore: coordinator.scores[$0]?.overallScore) }
        }
        rebuildReviewQueue()
    }

    private func rebuildReviewQueue() {
        reviewItems = ReviewQueueBuilder.build(
            singleReasons: flaggedSingles,
            burstGroups: criteria.flagBurstDuplicates ? burstGroups : [],
            duplicateGroups: duplicateGroupsWithScores
        )
    }
}
