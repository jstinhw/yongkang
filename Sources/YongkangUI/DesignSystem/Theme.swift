import AppKit
import SwiftUI

/// The console's whole visual vocabulary in one place: a cool near-black ground, one blue
/// accent, and the notebook's own `status:` words as the only other colour. Every screen is
/// built from these tokens, so a change here is a change everywhere.
///
/// Every colour is named for the job it does, not for what it looks like, so a repaint is a
/// value change here rather than a hunt through the features. Nothing outside this folder
/// writes a hex literal; `NoStrayTokensTests` fails the build if something does.
///
/// The values are fixed sRGB rather than the dynamic `NSColor(name:dynamicProvider:)` D16
/// asks for. Dynamic would be pixel-safe: `RootView` pins `.preferredColorScheme(.dark)`,
/// so the window is always `darkAqua` and a provider would only ever run its dark branch.
/// (Measured, not assumed — a dynamic colour and this literal render identical bytes in a
/// `darkAqua` window, and differ in an `aqua` one.) It would also be inert, because there
/// is no light palette yet: both branches would return the value below, and the pinned
/// scheme would keep the second one from ever running. Dynamic arrives with the palette
/// that gives it something to return, in the PR that also drops that pin.
package enum Theme {

    // MARK: - Ground
    //
    // One ramp from the rail out to a selected row. A surface is chosen by how far forward
    // it sits, which is why `raised` serves a hover, a chip and a button alike.

    static let rail = Color(hex: 0x0A0C10)  // the icon rail, one step darker
    package static let bg = Color(hex: 0x0C0E12)  // window ground
    static let panel = Color(hex: 0x0E1116)  // list and inspector columns, and code blocks
    static let well = Color(hex: 0x12161E)  // a sunken area inside a card: transcripts, quotes
    static let card = Color(hex: 0x141821)  // raised surface
    static let nested = Color(hex: 0x151A22)  // a card sitting on a card
    static let railActive = Color(hex: 0x161C26)  // the rail's selected item
    static let raised = Color(hex: 0x171C25)  // hover / selected surface, chips, buttons
    static let dotGrid = Color(hex: 0x1A202A)  // the board canvas's dots

    // MARK: - Edges
    //
    // ponytail: nine borders across 0x1C–0x2B is a ramp, not a system, and the type ramp it
    // was named alongside has since collapsed to eight roles. This one has not: 5.2 was
    // typography and the app icon, and repainting edges in the same PR would have made every
    // shot unreadable as evidence for either. Collapsing them to three or four is a value
    // change here plus whatever it renames — the palette PR, with its own before/after shots.

    static let wellLine = Color(hex: 0x1E242F)  // a well's edge, and a meter's empty track
    static let line = Color(hex: 0x1C212B)  // column and bar separators
    static let line2 = Color(hex: 0x212734)  // card borders
    static let nestedLine = Color(hex: 0x222937)  // a card sitting on a card
    static let stepLine = Color(hex: 0x242B37)  // a transcript step's glyph
    static let chipLine = Color(hex: 0x252C39)  // a fact chip
    static let controlLine = Color(hex: 0x262D3A)  // a button, and the dashed new-project tile
    static let hairline = Color(hex: 0x2A3240)  // selected outline
    static let markLine = Color(hex: 0x2B3B52)  // the app icon tile's inner edge

    // MARK: - Ink

    static let tx = Color(hex: 0xE7EBF1)
    static let prose = Color(hex: 0xC7D0DC)  // body copy: notebook text, resolutions, answers
    static let tx2 = Color(hex: 0x98A3B2)
    static let tx3 = Color(hex: 0x626C7B)
    static let tx4 = Color(hex: 0x39424F)

    // MARK: - Diff and failure ink
    //
    // The signal hues again, but pale enough to read a paragraph in. A diff is the one place
    // the app asks you to read colour-coded text rather than glance at it.

    static let insertion = Color(hex: 0xB6EBD5)  // a line the diff added
    static let problem = Color(hex: 0xF1BDBD)  // a removed line, an error, a denied command
    static let hunk = Color(hex: 0x5F9FE0)  // a diff's @@ position header
    static let unchanged = Color(hex: 0x8C97A6)  // a context line, carried by both sides

    // MARK: - Signal
    //
    // One accent; the rest are the notebook's status words. Same lightness and chroma,
    // different hue, so nothing shouts louder than anything else.

    static let accent = Color(hex: 0x52A8FF)  // active — an agent is on it
    static let green = Color(hex: 0x45D8A4)  // done — checked off
    package static let amber = Color(hex: 0xF3B455)  // blocked — waiting on you
    static let red = Color(hex: 0xFF6F6F)  // failed — its own check failed
    static let violet = Color(hex: 0xA98CFF)  // wip — a session already holds it

    // MARK: - App icon
    //
    // The icon's own ground, lit from the top-left. It is the one surface read at 16 px on
    // someone else's Dock rather than inside a window, so it needs a gradient the flat
    // `bg` above cannot give it. Nothing else draws with these.

    static let iconLit = Color(hex: 0x18202E)  // the tile's top-left corner
    static let iconShade = Color(hex: 0x0C1014)  // its bottom-right

    // MARK: - Metrics

    // Two of these are still fixed widths the app draws; `listWidth` is now only the width the
    // list opens at before it has been dragged, which `ListDivider` then remembers. The top bar's height
    // is gone with the bar: the window's title bar decides how tall it is.

    static let railWidth: CGFloat = 64
    package static let listWidth: CGFloat = 268  // the width the list opens at, until dragged
    static let inspectorWidth: CGFloat = 320
    static let actionBarHeight: CGFloat = 58
}

extension Color {
    /// How CSS writes this colour, for the one page the app draws in HTML (`PlanPage`), so a
    /// plan is painted from these tokens rather than from hex the page spells out again.
    var css: String {
        let rgb = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let byte = { (component: CGFloat) in Int((component * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
