import SwiftUI
import UIKit

/// Lists videos at 4K or above and recodes each one down to a smaller
/// resolution on demand — same bitrate, same color space, only the pixel
/// dimensions shrink (see `VideoRecoder`). Recoding never happens
/// automatically or in bulk: per-row, one at a time, same "nothing happens
/// without a tap" posture as the rest of the app. A successful recode adds
/// the smaller video as a new asset and stages the original in the same
/// trash the rest of the app already uses (`TrashView`).
struct VideoRecodeView: View {
    let ids: [String]
    let coordinator: AnalysisCoordinator

    @State private var target: VideoRecoder.Target = .p1080
    @State private var recodedIDs: Set<String> = []

    private var remainingIDs: [String] {
        ids.filter { !recodedIDs.contains($0) }
    }

    var body: some View {
        List {
            Section {
                Picker("Resolución destino", selection: $target) {
                    ForEach(VideoRecoder.Target.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text("Se conservan el bitrate y el espacio de color originales: solo cambia la resolución. El vídeo recodificado se añade como uno nuevo y el original pasa a la papelera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if remainingIDs.isEmpty {
                Text("No quedan vídeos 4K por recodificar.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(remainingIDs, id: \.self) { id in
                    VideoRecodeRow(assetID: id, target: target, coordinator: coordinator) {
                        recodedIDs.insert(id)
                    }
                }
            }
        }
        .navigationTitle("Vídeos 4K")
    }
}

private struct VideoRecodeRow: View {
    let assetID: String
    let target: VideoRecoder.Target
    let coordinator: AnalysisCoordinator
    let onRecoded: () -> Void

    @State private var thumbnail: UIImage?
    @State private var resolutionLabel = ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle
        case recoding(Double)
        case failed(String)
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
                Text(resolutionLabel)
                    .font(.subheadline)
                if case .failed(let message) = status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            actionView
        }
        .task(id: assetID) {
            guard let asset = await PhotoLibrary.shared.asset(withID: assetID) else { return }
            resolutionLabel = "\(asset.pixelWidth)×\(asset.pixelHeight)"
            let result = await PhotoLibrary.shared.thumbnail(for: asset, targetSize: CGSize(width: 120, height: 120))
            if case .available(let image) = result {
                thumbnail = image
            }
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch status {
        case .idle, .failed:
            Button("Recodificar") {
                Task { await recode() }
            }
            .buttonStyle(.bordered)
            .tint(.clearerAmber)
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

    private func recode() async {
        status = .recoding(0)
        do {
            _ = try await coordinator.recodeVideo(id: assetID, to: target) { progress in
                Task { @MainActor in status = .recoding(progress) }
            }
            onRecoded()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
