import Photos
import SwiftUI

/// Fase 2's whole surface: pick which criteria matter, run the analysis,
/// see counts. Deliberately doesn't let you act on anything yet — swiping
/// through and deleting is Fase 3. This is "how many, of what kind", not
/// "review and clean."
struct AnalysisResultsView: View {
    let fetchResult: PHFetchResult<PHAsset>
    let coordinator: AnalysisCoordinator

    @State private var criteria = CleanupCriteria()
    @State private var duplicateThreshold: Float = 0.35
    @State private var counts: [CleanupReason: Int] = [:]
    @State private var duplicateGroupCount = 0
    @State private var hasAnalyzed = false

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
            hasAnalyzed = true
            recomputeCounts()
            recomputeDuplicateGroups()
        }
    }

    /// Cheap: just property reads off already-fetched `PHAsset`s plus
    /// dictionary lookups into the coordinator's cache. No PhotoKit or
    /// Vision I/O here, so running this synchronously on every criteria
    /// toggle is fine even for large libraries.
    private func recomputeCounts() {
        var tally: [CleanupReason: Int] = [:]
        var burstsByID: [String: [(id: String, overallScore: Float?)]] = [:]

        for index in 0..<fetchResult.count {
            let asset = fetchResult.object(at: index)
            let cached = coordinator.scores[asset.localIdentifier]
            let signals = AssetSignals(
                mediaType: asset.mediaType,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
                burstIdentifier: asset.burstIdentifier,
                duration: asset.duration,
                overallScore: cached?.overallScore,
                isUtility: cached?.isUtility
            )
            for reason in Detectors.reasons(for: signals, criteria: criteria) {
                tally[reason, default: 0] += 1
            }
            if let burstID = asset.burstIdentifier {
                burstsByID[burstID, default: []].append((asset.localIdentifier, cached?.overallScore))
            }
        }

        if criteria.flagBurstDuplicates {
            tally[.burstDuplicate] = burstsByID.values.reduce(0) { total, burst in
                total + Detectors.burstDuplicateIDs(in: burst).count
            }
        }

        counts = tally
    }

    /// Only re-runs `Grouping`, not Vision — feature prints are already in
    /// memory, so dragging the slider is cheap and live.
    private func recomputeDuplicateGroups() {
        // Must stay in creation-date order (how `fetchResult` is already
        // sorted) — `Grouping` assumes near-duplicates are adjacent.
        let orderedIDs = (0..<fetchResult.count).compactMap { index -> String? in
            let id = fetchResult.object(at: index).localIdentifier
            return coordinator.featurePrints[id] != nil ? id : nil
        }
        duplicateGroupCount = Grouping.groups(
            ids: orderedIDs,
            threshold: duplicateThreshold,
            distance: coordinator.featurePrintDistance
        ).count
    }
}
