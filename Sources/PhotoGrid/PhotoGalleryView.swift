import SwiftUI
import UIKit

/// Every photo the analysis flagged, all at once, as a pinchable grid — the
/// same "act without leaving the grid" idea as `VideoModeView`, but for
/// stills. Tap toggles the trash mark right on the cell (no full-screen
/// hop); a long-press opens `PhotoViewer` for a closer look before
/// deciding. Marking here calls the exact same `AnalysisCoordinator`
/// methods as `ReviewView`'s one-at-a-time flow (`markForDeletion` +
/// `markReviewed`), so a photo decided here won't show up again in
/// `ReviewView`, and vice versa.
struct PhotoGalleryView: View {
    let reviewItems: [ReviewItem]
    let estimatedSizes: [String: Int64]
    let coordinator: AnalysisCoordinator

    @State private var columnCount = 4
    @State private var store = ReviewImageStore() // only for PhotoViewer's "Descargar original"
    @State private var viewerTarget: ViewerTarget?

    private struct ViewerTarget: Identifiable {
        let id: String
        let thumbnail: UIImage?
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(reviewItems) { item in
                    GalleryCell(
                        item: item,
                        estimatedBytes: estimatedSizes[item.id],
                        coordinator: coordinator,
                        showsSizeLabel: columnCount <= 4,
                        onLongPress: { thumbnail in
                            viewerTarget = ViewerTarget(id: item.id, thumbnail: thumbnail)
                        }
                    )
                }
            }
        }
        // Only committed on `.onEnded` — recomputing `columns` on every
        // `.onChanged` tick would force a full `LazyVGrid` relayout per
        // frame of the pinch, which shows with hundreds of cells.
        .simultaneousGesture(
            MagnifyGesture()
                .onEnded { value in
                    // Dividing, not multiplying: opening the fingers
                    // (magnification > 1) should mean FEWER columns
                    // (bigger photos), not more.
                    let proposed = Int((Double(columnCount) / value.magnification).rounded())
                    columnCount = min(max(proposed, 2), 8)
                }
        )
        .navigationTitle("Galería (\(reviewItems.count))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrashView(coordinator: coordinator)
                } label: {
                    Label("\(coordinator.pendingDeletionIDs.count)", systemImage: "trash")
                }
            }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            PhotoViewer(
                assetID: target.id,
                store: store,
                thumbnail: target.thumbnail,
                onDecision: { shouldDelete in
                    if shouldDelete {
                        coordinator.markForDeletion(target.id)
                    } else {
                        coordinator.unmarkForDeletion(target.id)
                    }
                    coordinator.markReviewed(target.id)
                    viewerTarget = nil
                },
                onClose: { viewerTarget = nil }
            )
        }
    }
}

private struct GalleryCell: View {
    let item: ReviewItem
    let estimatedBytes: Int64?
    let coordinator: AnalysisCoordinator
    let showsSizeLabel: Bool
    let onLongPress: (UIImage?) -> Void

    @State private var thumbnail: UIImage?

    private var isMarked: Bool { coordinator.pendingDeletionIDs.contains(item.id) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(.quaternary)
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            }
            if isMarked {
                Color.black.opacity(0.45)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.clearerBrick)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showsSizeLabel, let estimatedBytes {
                sizeLabel(estimatedBytes)
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { toggleMark() }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onLongPress(thumbnail) }
        )
        .task(id: item.id) {
            guard let asset = await PhotoLibrary.shared.asset(withID: item.id) else { return }
            let result = await PhotoLibrary.shared.thumbnail(for: asset, targetSize: CGSize(width: 200, height: 200))
            if case .available(let image) = result {
                thumbnail = image
            }
        }
    }

    // Flat, monochrome scrim — same treatment as `PhotoGridCell`'s iCloud
    // badge, never a decorative pill.
    private func sizeLabel(_ bytes: Int64) -> some View {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return Text("~" + formatter.string(fromByteCount: bytes))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
    }

    private func toggleMark() {
        if isMarked {
            coordinator.unmarkForDeletion(item.id)
        } else {
            coordinator.markForDeletion(item.id)
        }
        coordinator.markReviewed(item.id)
    }
}
