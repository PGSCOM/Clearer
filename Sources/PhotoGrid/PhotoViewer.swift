import SwiftUI
import UIKit

/// Full-screen photo inspection: real pinch/pan/double-tap zoom via
/// `ZoomableImageView`, the original-download control, and the same large
/// Keep/Delete buttons as the review card — deciding here closes the
/// viewer too, so looking closely at a photo doesn't cost an extra tap on
/// top of the decision itself.
struct PhotoViewer: View {
    let assetID: String
    let store: ReviewImageStore
    let thumbnail: UIImage?
    let onDecision: (_ shouldDelete: Bool) -> Void
    let onClose: () -> Void

    private var displayedImage: UIImage? {
        (store.fullResID == assetID ? store.fullResImage : nil) ?? thumbnail
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZoomableImageView(image: displayedImage)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomControls
            }
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Cerrar")
            .accessibilityIdentifier("closeViewer")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 18) {
            downloadControl
            HStack(spacing: 16) {
                Button("Mantener") { onDecision(false) }
                    .buttonStyle(.reviewKeep)
                Button("Eliminar", role: .destructive) { onDecision(true) }
                    .buttonStyle(.reviewDelete)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        switch store.downloadState {
        case .idle:
            Button {
                store.downloadOriginal(id: assetID)
            } label: {
                Label("Descargar original", systemImage: "icloud.and.arrow.down")
            }
            .buttonStyle(ViewerCapsuleButtonStyle())

        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .tint(.white)
                    .frame(width: 110)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                Button("Cancelar") { store.cancelDownload() }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())

        case .done:
            Label("Original descargado", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())

        case .failed:
            Button {
                store.downloadOriginal(id: assetID)
            } label: {
                Label("Reintentar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ViewerCapsuleButtonStyle())
        }
    }
}

/// Flat, monochrome — a functional scrim so a white icon+label stays
/// legible over whatever photo happens to be behind it, not a decorative
/// gradient pill.
private struct ViewerCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
