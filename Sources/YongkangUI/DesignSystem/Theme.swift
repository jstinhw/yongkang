import SwiftUI

/// The console's whole visual vocabulary in one place: a cool near-black ground, one blue
/// accent, and the notebook's own `status:` words as the only other colour. Every screen is
/// built from these tokens, so a change here is a change everywhere.
package enum Theme {

    // MARK: - Ground

    package static let bg = Color(hex: 0x0C0E12)  // window ground
    static let rail = Color(hex: 0x0A0C10)  // the icon rail, one step darker
    static let panel = Color(hex: 0x0E1116)  // list and inspector columns
    static let card = Color(hex: 0x141821)  // raised surface
    static let raised = Color(hex: 0x171C25)  // hover / selected surface
    static let line = Color(hex: 0x1C212B)  // column and bar separators
    static let line2 = Color(hex: 0x212734)  // card borders
    static let hairline = Color(hex: 0x2A3240)  // selected outline

    // MARK: - Ink

    static let tx = Color(hex: 0xE7EBF1)
    static let tx2 = Color(hex: 0x98A3B2)
    static let tx3 = Color(hex: 0x626C7B)
    static let tx4 = Color(hex: 0x39424F)

    // MARK: - Signal
    //
    // One accent; the rest are the notebook's status words. Same lightness and chroma,
    // different hue, so nothing shouts louder than anything else.

    static let accent = Color(hex: 0x52A8FF)  // active — an agent is on it
    static let green = Color(hex: 0x45D8A4)  // done — QA passed
    package static let amber = Color(hex: 0xF3B455)  // blocked — waiting on you
    static let red = Color(hex: 0xFF6F6F)  // failed — QA sent it back
    static let violet = Color(hex: 0xA98CFF)  // wip — a lead already holds it

    // MARK: - Metrics

    static let railWidth: CGFloat = 64
    static let listWidth: CGFloat = 268
    static let inspectorWidth: CGFloat = 320
    static let topBarHeight: CGFloat = 56
    static let actionBarHeight: CGFloat = 58
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
