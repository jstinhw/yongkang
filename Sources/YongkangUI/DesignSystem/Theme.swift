import SwiftUI

/// The console's whole visual vocabulary in one place: a cool near-black ground, one blue
/// accent, and the notebook's own `status:` words as the only other colour. Every screen is
/// built from these tokens, so a change here is a change everywhere.
///
/// Every colour is named for the job it does, not for what it looks like, so a repaint is a
/// value change here rather than a hunt through the features. Nothing outside this folder
/// writes a hex literal; `NoStrayTokensTests` fails the build if something does.
///
/// The values are fixed sRGB rather than dynamic `NSColor(name:dynamicProvider:)` on
/// purpose. The app pins no appearance, so its dark ground comes from these literals alone;
/// a dynamic colour whose light branch differed would repaint the app on a light-mode Mac,
/// and one whose branches matched would be a light theme in name only. D16 asks for dynamic
/// values — they arrive with the light palette that gives them a second branch to return,
/// and then it is these 41 lines that change.
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
    static let mark = Color(hex: 0x141C28)  // the "YK" identity tile
    static let nested = Color(hex: 0x151A22)  // a card sitting on a card
    static let railActive = Color(hex: 0x161C26)  // the rail's selected item
    static let raised = Color(hex: 0x171C25)  // hover / selected surface, chips, buttons
    static let dotGrid = Color(hex: 0x1A202A)  // the board canvas's dots

    // MARK: - Edges
    //
    // ponytail: eight borders across 0x1C–0x2B is a ramp, not a system. Naming them is as
    // far as a no-visual-change PR can go; 5.2's canvas is where they collapse to three or
    // four, which is a value change here plus whatever it renames.

    static let wellLine = Color(hex: 0x1E242F)  // a well's edge, and a meter's empty track
    static let line = Color(hex: 0x1C212B)  // column and bar separators
    static let line2 = Color(hex: 0x212734)  // card borders
    static let nestedLine = Color(hex: 0x222937)  // a card sitting on a card
    static let stepLine = Color(hex: 0x242B37)  // a transcript step's glyph
    static let chipLine = Color(hex: 0x252C39)  // a fact chip
    static let controlLine = Color(hex: 0x262D3A)  // a button, and the dashed new-project tile
    static let hairline = Color(hex: 0x2A3240)  // selected outline
    static let markLine = Color(hex: 0x2B3B52)  // the "YK" identity tile

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
