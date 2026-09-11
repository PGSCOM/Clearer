import SwiftUI
import UIKit

/// One card at a time: keep it, or send it to the trash for later
/// confirmation. Nothing here is destructive by itself — "Eliminar" only
/// stages the asset in `coordinator.pendingDeletionIDs`; the actual delete
/// (with iOS's own confirmation) happens in `TrashView`.
///
/// Built for a review session of thousands of photos, not a handful:
/// thumbnails prefetch a few cards ahead (`ReviewImageStore`), where you
/// left off is saved (`ReviewProgressRecord`) so leaving mid-way doesn't
/// mean starting over, and a wrong tap can be undone.
///
/// `pendingQueue` + `cursor` — not a live filter of `reviewItems` on every
/// access — is what keeps this responsive at scale: the correct-but-O(n)
/// `ReviewQueueBuilder.pending` filter runs exactly once, on appear, to
/// resume from persisted progress; every decision after that is an O(1)
/// cursor move.
struct ReviewView: View {
    let reviewItems: [ReviewItem]
    let coordinator: AnalysisCoordinator

    @State private var store = ReviewImageStore()

    @State private var pendingQueue: [ReviewItem] = []
    @State private var cursor = 0
    @State private var history: [Decision] = []
    @State private var showViewer = false

    private struct Decision {
        let itemID: String
        let wasDeleted: Bool
    }

    private var currentItem: ReviewItem? {
        cursor < pendingQueue.count ? pendingQueue[cursor] : nil
    }

    private var cardTargetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: UIScreen.main.bounds.width * scale, height: UIScreen.main.bounds.height * scale)
    }

    var body: some View {
        VStack(spacing: 20) {
            if let item = currentItem {
                ReviewCard(
                    item: item,
                    store: store,
                    targetSize: cardTargetSize,
                    onOpenViewer: { showViewer = true },
                    onDecision: decide
                )
                .id(item.id)
                Text("\(cursor + 1) de \(reviewItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                doneView
            }
        }
        .padding()
        .navigationTitle("Revisar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(history.isEmpty)
                .accessibilityLabel("Deshacer")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrashView(coordinator: coordinator)
                } label: {
                    Label("\(coordinator.pendingDeletionIDs.count)", systemImage: "trash")
                }
            }
        }
        .fullScreenCover(isPresented: $showViewer) {
            if let item = currentItem {
                PhotoViewer(
                    assetID: item.id,
                    store: store,
                    thumbnail: store.thumbnails[item.id],
                    onDecision: { shouldDelete in
                        showViewer = false
                        decide(item, shouldDelete: shouldDelete)
                    },
                    onClose: { showViewer = false }
                )
            }
        }
        .task {
            pendingQueue = ReviewQueueBuilder.pending(items: reviewItems, reviewed: coordinator.reviewedIDs)
            cursor = 0
            store.resetFullRes(for: currentItem?.id)
            updatePrefetch()
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
            .buttonStyle(.amberFilled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func decide(_ item: ReviewItem, shouldDelete: Bool) {
        guard currentItem?.id == item.id else { return } // stale callback (e.g. viewer closing) — ignore
        if shouldDelete {
            coordinator.markForDeletion(item.id)
        }
        coordinator.markReviewed(item.id)
        history.append(Decision(itemID: item.id, wasDeleted: shouldDelete))
        cursor += 1
        store.resetFullRes(for: currentItem?.id)
        updatePrefetch()
    }

    private func undo() {
        guard let last = history.popLast(), cursor > 0 else { return }
        if last.wasDeleted {
            coordinator.unmarkForDeletion(last.itemID)
        }
        coordinator.unmarkReviewed(last.itemID)
        cursor -= 1
        store.resetFullRes(for: currentItem?.id)
        updatePrefetch()
    }

    /// Keeps a handful of thumbnails warm around the current card — see
    /// `ReviewImageStore.keepWarmIDs` for the actual windowing logic. Both
    /// slices here are bounded by a small constant regardless of queue
    /// size: `pendingQueue[cursor...]` is an O(1) view, and only its first
    /// few elements ever get mapped to IDs.
    private func updatePrefetch() {
        let upcoming = pendingQueue[cursor...].prefix(4).map(\.id)
        let recent = history.suffix(1).map(\.itemID)
        let keep = ReviewImageStore.keepWarmIDs(pending: Array(upcoming), recentlyReviewed: recent)
        store.updateWindow(keepIDs: keep, targetSize: cardTargetSize)
    }
}

private struct ReviewCard: View {
    let item: ReviewItem
    let store: ReviewImageStore
    let targetSize: CGSize
    let onOpenViewer: () -> Void
    let onDecision: (_ item: ReviewItem, _ shouldDelete: Bool) -> Void

    @State private var pinchScale: CGFloat = 1

    private var displayedImage: UIImage? {
        (store.fullResID == item.id ? store.fullResImage : nil) ?? store.thumbnails[item.id]
    }

    var body: some View {
        VStack(spacing: 16) {
            photo
            reasonLine
            downloadRow
            decisionButtons
        }
    }

    private var photo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(.quaternary)
            if let displayedImage {
                Image(uiImage: displayedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if store.failedIDs.contains(item.id) {
                failedPlaceholder
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("reviewPhoto")
        .scaleEffect(pinchScale)
        .onTapGesture { onOpenViewer() }
        // `.simultaneousGesture`, not `.gesture` — SwiftUI treats two
        // `.gesture()`-attached recognizers on one view as exclusive by
        // default, and a plain tap should still open the viewer even
        // though a pinch also can.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    pinchScale = min(value.magnification, 1.3)
                }
                .onEnded { value in
                    let didPinchOpen = value.magnification > 1.15
                    withAnimation(.easeOut(duration: 0.15)) { pinchScale = 1 }
                    if didPinchOpen { onOpenViewer() }
                }
        )
    }

    private var failedPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No se pudo cargar la foto")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Reintentar") {
                store.retry(id: item.id, targetSize: targetSize)
            }
            .buttonStyle(.bordered)
            .tint(.clearerAmber)
        }
    }

    private var reasonLine: some View {
        Text(item.reasons.sorted(by: { $0.rawValue < $1.rawValue }).map(reasonLabel).joined(separator: " · "))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var downloadRow: some View {
        switch store.downloadState {
        case .idle:
            Button {
                store.downloadOriginal(id: item.id)
            } label: {
                Label("Descargar original", systemImage: "icloud.and.arrow.down")
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        case .downloading(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress).frame(width: 70)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .done:
            Label("Original descargado", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        case .failed:
            Button {
                store.downloadOriginal(id: item.id)
            } label: {
                Label("Reintentar", systemImage: "arrow.clockwise")
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var decisionButtons: some View {
        HStack(spacing: 16) {
            Button("Mantener") { onDecision(item, false) }
                .buttonStyle(.reviewKeep)
            Button("Eliminar", role: .destructive) { onDecision(item, true) }
                .buttonStyle(.reviewDelete)
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
