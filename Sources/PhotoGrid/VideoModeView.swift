import Photos
import SwiftUI
import UIKit

/// Every video in the library, largest-on-disk first, so the ones actually
/// worth shrinking surface without having to run "Analizar fototeca" first
/// — videos skip the Vision pass entirely (see `AnalysisCoordinator.analyze`),
/// so this stands on its own as a separate mode. Recode to a smaller
/// resolution (bitrate and color space preserved, see `VideoRecoder`) or
/// delete outright, both staging into the same trash `TrashView` shows.
///
/// The list appears instantly using the cheap pixel/duration estimate from
/// `SpaceEstimator`, then `AnalysisCoordinator.measureVideoSizes` reads real
/// on-disk byte sizes in the background and the list re-sorts ONCE when
/// that finishes — not on every batch, or rows would jump under the user's
/// finger mid-measurement.
struct VideoModeView: View {
    let coordinator: AnalysisCoordinator

    @State private var rows: [VideoRow] = []

    private var visibleRows: [VideoRow] {
        rows.filter { !coordinator.pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        List {
            if coordinator.isMeasuringVideoSizes {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Midiendo tamaños reales… \(coordinator.measuredVideoCount) de \(coordinator.totalVideoCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if visibleRows.isEmpty {
                Text(rows.isEmpty ? "No hay vídeos en tu fototeca." : "No quedan vídeos por recodificar o borrar.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleRows) { row in
                    VideoModeRow(row: row, coordinator: coordinator)
                }
            }
        }
        .navigationTitle("Vídeos")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrashView(coordinator: coordinator)
                } label: {
                    Label("\(coordinator.pendingDeletionIDs.count)", systemImage: "trash")
                }
            }
        }
        .task {
            let fetchResult = await PhotoLibrary.shared.fetchAllVideos()
            rebuildRows(from: fetchResult) // instant, estimate-based order
            await coordinator.measureVideoSizes(fetchResult)
            rebuildRows(from: fetchResult) // one re-sort, now with real sizes
        }
    }

    private func rebuildRows(from fetchResult: PHFetchResult<PHAsset>) {
        var built: [VideoRow] = []
        built.reserveCapacity(fetchResult.count)
        for index in 0..<fetchResult.count {
            let asset = fetchResult.object(at: index)
            let id = asset.localIdentifier
            let realSize = coordinator.videoSizes[id]
            let bytes: Int64
            let isEstimate: Bool
            if let realSize, realSize > 0 {
                bytes = realSize
                isEstimate = false
            } else {
                bytes = SpaceEstimator.estimatedBytes(
                    mediaType: .video, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight, duration: asset.duration
                )
                isEstimate = true
            }
            built.append(VideoRow(
                id: id, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                duration: asset.duration, bytes: bytes, isEstimate: isEstimate
            ))
        }
        rows = built.sorted { $0.bytes > $1.bytes }
    }
}

/// One video's display data, snapshotted off `PHAsset` — not the asset
/// itself, so re-sorting `VideoModeView.rows` is a pure array sort, no
/// PhotoKit touches.
private struct VideoRow: Identifiable {
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let bytes: Int64
    let isEstimate: Bool
}

private struct VideoModeRow: View {
    let row: VideoRow
    let coordinator: AnalysisCoordinator

    @State private var thumbnail: UIImage?
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle
        case recoding(Double)
        case failed(String)
    }

    private var validTargets: [VideoRecoder.Target] {
        let longEdge = CGFloat(max(row.pixelWidth, row.pixelHeight))
        return VideoRecoder.Target.allCases.filter { $0.longEdge < longEdge }
    }

    private var sizeLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: row.bytes)
        return row.isEstimate ? "~\(formatted)" : formatted
    }

    var body: some View {
        HStack {
            ZStack {
                Rectangle().fill(.quaternary)
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.pixelWidth)×\(row.pixelHeight)")
                    .font(.subheadline)
                Text(sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            actionView
        }
        .task(id: row.id) {
            guard let asset = await PhotoLibrary.shared.asset(withID: row.id) else { return }
            let result = await PhotoLibrary.shared.thumbnail(for: asset, targetSize: CGSize(width: 120, height: 120))
            if case .available(let image) = result {
                thumbnail = image
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                coordinator.markForDeletion(row.id)
                coordinator.markReviewed(row.id)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch status {
        case .idle, .failed:
            if validTargets.isEmpty {
                Text("Ya es pequeño")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(validTargets) { option in
                        Button(option.label) {
                            Task { await recode(to: option) }
                        }
                    }
                } label: {
                    Label("Recodificar", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .tint(.clearerAmber)
            }
        case .recoding(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress).frame(width: 60)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func recode(to target: VideoRecoder.Target) async {
        status = .recoding(0)
        do {
            _ = try await coordinator.recodeVideo(id: row.id, to: target) { progress in
                Task { @MainActor in status = .recoding(progress) }
            }
            // Row disappears on its own next render: `recodeVideo` already
            // staged the original in `pendingDeletionIDs`, which
            // `VideoModeView.visibleRows` filters against.
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
