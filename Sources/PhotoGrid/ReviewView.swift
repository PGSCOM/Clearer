import SwiftUI
import UIKit

/// One card at a time: keep it, or send it to the trash for later
/// confirmation. Nothing here is destructive by itself — "Eliminar" only
/// stages the asset in `coordinator.pendingDeletionIDs`; the actual delete
/// (with iOS's own confirmation) happens in `TrashView`.
struct ReviewView: View {
    let reviewItems: [ReviewItem]
    let coordinator: AnalysisCoordinator

    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 20) {
            if currentIndex < reviewItems.count {
                let item = reviewItems[currentIndex]
                ReviewCard(assetID: item.id, reasons: item.reasons) { shouldDelete in
                    if shouldDelete {
                        coordinator.markForDeletion(item.id)
                    }
                    currentIndex += 1
                }
                Text("\(currentIndex + 1) de \(reviewItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                doneView
            }
        }
        .padding()
        .navigationTitle("Revisar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrashView(coordinator: coordinator)
                } label: {
                    Label("\(coordinator.pendingDeletionIDs.count)", systemImage: "trash")
                }
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Has revisado todo")
                .font(.title3.weight(.semibold))
            NavigationLink {
                TrashView(coordinator: coordinator)
            } label: {
                Text("Ir a la papelera (\(coordinator.pendingDeletionIDs.count))")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReviewCard: View {
    let assetID: String
    let reasons: Set<CleanupReason>
    let onDecision: (_ shouldDelete: Bool) -> Void

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.quaternary)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxHeight: 420)

            HStack(spacing: 6) {
                ForEach(Array(reasons).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { reason in
                    Text(reasonLabel(reason))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }

            // Both filled, same weight, differentiated by color alone — not
            // the stock filled-plus-outlined pairing. "Keep" isn't the
            // lesser option here; ghosting it as an outline would wrongly
            // suggest "Delete" is the default expected action.
            HStack(spacing: 16) {
                Button("Mantener") { onDecision(false) }
                    .buttonStyle(.amberFilled)
                    .frame(maxWidth: .infinity)
                Button("Eliminar", role: .destructive) { onDecision(true) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: assetID) {
            image = nil
            guard let asset = await PhotoLibrary.shared.asset(withID: assetID) else { return }
            let result = await PhotoLibrary.shared.thumbnail(for: asset, targetSize: CGSize(width: 900, height: 900))
            if case .available(let fetched) = result {
                image = fetched
            }
        }
    }

    private func reasonLabel(_ reason: CleanupReason) -> String {
        switch reason {
        case .screenshot: "Captura"
        case .utility: "Documento"
        case .lowQuality: "Baja calidad"
        case .longVideo: "Vídeo largo"
        case .burstDuplicate: "Ráfaga"
        case .duplicate: "Parecida a otra"
        }
    }
}
