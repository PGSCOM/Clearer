import SwiftUI
import UIKit

/// The app's own trash, staged before anything actually happens. Confirming
/// here calls PhotoKit's real delete — which pops iOS's own native
/// confirmation alert on top of this, a second, unskippable checkpoint.
struct TrashView: View {
    let coordinator: AnalysisCoordinator

    @State private var estimatedBytes: Int64 = 0
    @State private var isDeleting = false
    @State private var lastResult: DeletionResult?

    var body: some View {
        List {
            if coordinator.pendingDeletionIDs.isEmpty {
                Text("La papelera está vacía.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.pendingDeletionIDs.sorted(), id: \.self) { id in
                    TrashRow(assetID: id) {
                        coordinator.unmarkForDeletion(id)
                    }
                }

                Section {
                    HStack {
                        Text("Espacio estimado")
                        Spacer()
                        Text(formattedEstimate)
                            .foregroundStyle(.secondary)
                    }
                    Text("Estimado a partir del tamaño de la imagen y la duración del vídeo — no hay forma de leer el peso exacto sin descargar el archivo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await confirmDeletion() }
                    } label: {
                        if isDeleting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Borrar \(coordinator.pendingDeletionIDs.count) elementos")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isDeleting)
                }
            }

            if let lastResult {
                Section {
                    Text(lastResult.summary)
                        .foregroundStyle(lastResult.isSuccess ? .primary : .red)
                }
            }
        }
        .navigationTitle("Papelera")
        .task(id: coordinator.pendingDeletionIDs) {
            estimatedBytes = await coordinator.estimatedFreedBytes()
        }
    }

    private var formattedEstimate: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "~" + formatter.string(fromByteCount: estimatedBytes)
    }

    private func confirmDeletion() async {
        isDeleting = true
        defer { isDeleting = false }

        let ids = Array(coordinator.pendingDeletionIDs)
        do {
            try await withTimeout(seconds: 20) {
                try await PhotoLibrary.shared.deleteAssets(withIDs: ids)
            }
            coordinator.clearDeleted(ids)
            lastResult = .success(count: ids.count)
        } catch is TimeoutError {
            lastResult = .timedOut
        } catch {
            lastResult = .failure(error.localizedDescription)
        }
    }
}

private struct TrashRow: View {
    let assetID: String
    let onRemove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        HStack {
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button("Quitar", action: onRemove)
                .buttonStyle(.borderless)
        }
        .task(id: assetID) {
            guard let asset = await PhotoLibrary.shared.asset(withID: assetID) else { return }
            let result = await PhotoLibrary.shared.thumbnail(for: asset, targetSize: CGSize(width: 88, height: 88))
            if case .available(let fetched) = result {
                image = fetched
            }
        }
    }
}

private enum DeletionResult {
    case success(count: Int)
    case timedOut
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .success(let count):
            "Se borraron \(count) elementos."
        case .timedOut:
            "Está tardando más de lo normal. Puede que ya se haya completado — revisa tu fototeca; si no, inténtalo de nuevo."
        case .failure(let message):
            "No se pudo borrar: \(message)"
        }
    }
}
