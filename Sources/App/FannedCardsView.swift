import SwiftUI

/// The app's signature visual, alive on screen: the same fanned-photo-card
/// motif as the app icon (faint outlines receding into one solid "kept"
/// card). Settles into its fanned pose once on appear — a small, honest
/// touch of motion, never required to see the content, which renders fully
/// formed even with `isSettled` still false (respects Reduce Motion by
/// simply skipping the animation, not by hiding anything).
struct FannedCardsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    var body: some View {
        ZStack {
            ghostCard(rotation: -11, offset: CGSize(width: 26, height: -22), opacity: 0.16)
            ghostCard(rotation: -5.5, offset: CGSize(width: 13, height: -11), opacity: 0.32)
            keptCard()
        }
        .onAppear {
            guard !reduceMotion else {
                isSettled = true
                return
            }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.15)) {
                isSettled = true
            }
        }
    }

    private func ghostCard(rotation: Double, offset: CGSize, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.clearerCream, lineWidth: 3.5)
            .frame(width: 128, height: 160)
            .rotationEffect(.degrees(isSettled ? rotation : 0))
            .offset(isSettled ? offset : .zero)
            .opacity(opacity)
    }

    private func keptCard() -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.clearerCream)
            .frame(width: 128, height: 160)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.clearerAmber)
                    .frame(width: 26, height: 26)
                    .padding(12)
            }
    }
}

#Preview {
    FannedCardsView()
        .padding(80)
        .background(Color.clearerPine)
}
