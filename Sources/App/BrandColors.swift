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
}
