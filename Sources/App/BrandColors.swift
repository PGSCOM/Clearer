import SwiftUI

/// Plain Swift constants, not an asset-catalog color set — no way to
/// preview a hand-authored `.colorset/Contents.json` without Xcode, so
/// numeric literals I can review directly are the safer bet. Same values
/// as `IconGenerator/Sources/IconGenerator/IconGenerator.swift` — the icon
/// and the onboarding fanned-card motif are meant to be the same mark.
///
/// Fixed, not light/dark-adaptive: these carry the onboarding's deliberate
/// always-dark brand moment, not a system surface that needs to blend into
/// the user's chosen appearance. The rest of the app (grid, analysis,
/// review, trash) stays on system dynamic colors, correct in both
/// appearances by construction, with `clearerAmber` threaded through as
/// the one accent tying it back to the brand.
extension Color {
    static let clearerPine = Color(red: 0.043, green: 0.075, blue: 0.059)
    static let clearerCream = Color(red: 0.965, green: 0.945, blue: 0.902)
    static let clearerAmber = Color(red: 0.80, green: 0.55, blue: 0.28)
    /// The "Eliminar" counterpart to `clearerAmber` — a deep brick that
    /// belongs to the same warm pine/amber world instead of the system's
    /// saturated destructive red. Cream text on this lands ~7.5:1, clear of
    /// even the strict 4.5:1 WCAG floor for body-size text.
    static let clearerBrick = Color(red: 0.55, green: 0.16, blue: 0.13)
}

/// Explicit, not `.tint(.clearerAmber)` on top of `.borderedProminent`'s
/// automatic (usually white) label color — worked out the sRGB relative
/// luminance by hand and white text on this amber lands around a 2.9:1
/// contrast ratio, short of even the lenient 3:1 WCAG floor for bold text.
/// Dark pine text on the same amber lands closer to 3.6–4:1. A button
/// whose label doesn't stand clear of its own fill has failed at the one
/// thing it exists to do, so this is spelled out instead of trusted to
/// system defaults.
struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.clearerPine)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.clearerAmber, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == AmberButtonStyle {
    static var amberFilled: AmberButtonStyle { AmberButtonStyle() }
}

/// The large, always-paired Keep/Delete buttons in the review flow —
/// deliberately identical geometry (height, radius, weight) so the two sit
/// on the same grid instead of one looming over the other. Both filled, not
/// the stock filled-plus-outline pairing: "Keep" isn't a lesser option
/// here, so ghosting it as an outline would wrongly suggest "Delete" is the
/// default expected action. Sized for a decision repeated thousands of
/// times over one review session, not a one-off tap — a much bigger target
/// than a normal button has any reason to be.
struct ReviewDecisionButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.vertical, 18)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == ReviewDecisionButtonStyle {
    static var reviewKeep: ReviewDecisionButtonStyle {
        ReviewDecisionButtonStyle(fill: .clearerAmber, foreground: .clearerPine)
    }
    static var reviewDelete: ReviewDecisionButtonStyle {
        ReviewDecisionButtonStyle(fill: .clearerBrick, foreground: .clearerCream)
    }
}
