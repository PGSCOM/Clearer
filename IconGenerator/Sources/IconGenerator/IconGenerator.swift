import AppKit
import SwiftUI

/// The signature: a fanned stack of photo cards resolving from faint
/// outlines (the many) into one solid, kept card (the clear result) —
/// literally what this app does to a photo library. Deep warm pine-black
/// instead of the reflexive blue-charcoal dark default; warm bone/cream
/// instead of stark white; a single small amber mark on the kept card
/// instead of a checkmark cliché.
struct AppIconView: View {
    private let background = Color(red: 0.043, green: 0.075, blue: 0.059)
    private let cream = Color(red: 0.965, green: 0.945, blue: 0.902)
    private let amber = Color(red: 0.80, green: 0.55, blue: 0.28)

    var body: some View {
        ZStack {
            background

            ghostCard(rotation: -11, offset: CGSize(width: 100, height: -88), opacity: 0.14)
            ghostCard(rotation: -5.5, offset: CGSize(width: 50, height: -44), opacity: 0.30)
            keptCard()
        }
        .frame(width: 1024, height: 1024)
    }

    private func ghostCard(rotation: Double, offset: CGSize, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 72, style: .continuous)
            .strokeBorder(cream, lineWidth: 14)
            .frame(width: 460, height: 580)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .opacity(opacity)
    }

    private func keptCard() -> some View {
        RoundedRectangle(cornerRadius: 72, style: .continuous)
            .fill(cream)
            .frame(width: 460, height: 580)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(amber)
                    .frame(width: 92, height: 92)
                    .padding(44)
            }
    }
}

@main
struct IconGenerator {
    @MainActor
    static func main() {
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1

        guard let nsImage = renderer.nsImage else {
            print("Failed to render icon")
            exit(1)
        }
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("Failed to convert rendered icon to PNG")
            exit(1)
        }

        let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
        let url = URL(fileURLWithPath: outputPath)
        do {
            try pngData.write(to: url)
            print("Wrote icon to \(url.path)")
        } catch {
            print("Failed to write file: \(error)")
            exit(1)
        }
    }
}
