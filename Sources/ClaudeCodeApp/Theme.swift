import SwiftUI
import AppKit

/// The console's whole visual vocabulary in one place: a cool near-black ground, one blue
/// accent, and the notebook's own `status:` words as the only other colour. Every screen is
/// built from these tokens, so a change here is a change everywhere.
enum Theme {

    // MARK: - Ground

    static let bg      = Color(hex: 0x0C0E12)   // window ground
    static let rail    = Color(hex: 0x0A0C10)   // the icon rail, one step darker
    static let panel   = Color(hex: 0x0E1116)   // list and inspector columns
    static let card    = Color(hex: 0x141821)   // raised surface
    static let raised  = Color(hex: 0x171C25)   // hover / selected surface
    static let line    = Color(hex: 0x1C212B)   // column and bar separators
    static let line2   = Color(hex: 0x212734)   // card borders
    static let hairline = Color(hex: 0x2A3240)  // selected outline

    // MARK: - Ink

    static let tx  = Color(hex: 0xE7EBF1)
    static let tx2 = Color(hex: 0x98A3B2)
    static let tx3 = Color(hex: 0x626C7B)
    static let tx4 = Color(hex: 0x39424F)

    // MARK: - Signal
    //
    // One accent; the rest are the notebook's status words. Same lightness and chroma,
    // different hue, so nothing shouts louder than anything else.

    static let accent = Color(hex: 0x52A8FF)   // active — an agent is on it
    static let green  = Color(hex: 0x45D8A4)   // done — QA passed
    static let amber  = Color(hex: 0xF3B455)   // blocked — waiting on you
    static let red    = Color(hex: 0xFF6F6F)   // failed — QA sent it back
    static let violet = Color(hex: 0xA98CFF)   // wip — a lead already holds it

    // MARK: - Metrics

    static let railWidth: CGFloat = 64
    static let listWidth: CGFloat = 268
    static let inspectorWidth: CGFloat = 320
    static let topBarHeight: CGFloat = 56
    static let actionBarHeight: CGFloat = 58
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Three faces, each with one job: a display face for titles, a text face for prose, and a
/// mono for anything an agent typed — ids, paths, commands, diffs. Named faces are used
/// when they are installed and quietly fall back to the system stack when they are not, so
/// the app never ships a font it cannot draw.
enum Typo {
    private static func installed(_ name: String) -> Bool { NSFont(name: name, size: 12) != nil }

    private static let displayFace: String? = ["Space Grotesk"].first(where: installed)
    private static let textFace: String? = ["IBM Plex Sans"].first(where: installed)
    private static let monoFace: String? = ["JetBrains Mono", "SF Mono"].first(where: installed)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        guard let displayFace else { return .system(size: size, weight: weight) }
        return .custom(displayFace, size: size).weight(weight)
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let textFace else { return .system(size: size, weight: weight) }
        return .custom(textFace, size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let monoFace else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(monoFace, size: size).weight(weight)
    }

    /// The all-caps tracked label that heads every section on every screen.
    static let section = Font.system(size: 10, weight: .semibold)
}

/// A section heading: the same 10pt tracked caps everywhere, so panels read as one system.
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(Typo.section)
                .tracking(1.4)
                .foregroundStyle(Theme.tx3)
            if let trailing {
                Spacer(minLength: 8)
                Text(trailing).font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            }
        }
    }
}

/// A raised panel. Everything that is its own object on a screen sits on one of these.
struct CardSurface: ViewModifier {
    var radius: CGFloat = 12
    var padding: CGFloat = 14
    var border: Color = Theme.line2
    var fill: Color = Theme.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1))
    }
}

extension View {
    func cardSurface(radius: CGFloat = 12, padding: CGFloat = 14,
                     border: Color = Theme.line2, fill: Color = Theme.card) -> some View {
        modifier(CardSurface(radius: radius, padding: padding, border: border, fill: fill))
    }

    /// The selected row treatment used by every list column.
    func rowSelection(_ on: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 9).fill(on ? Theme.raised : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(on ? Theme.hairline : .clear, lineWidth: 1))
    }
}

/// The one button shape in the app. `primary` is the single action a screen is for; there
/// is never more than one on screen.
struct ConsoleButtonStyle: ButtonStyle {
    var primary = false
    var ghost = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.text(12, primary ? .semibold : .medium))
            .foregroundStyle(primary ? Theme.bg : (ghost ? Theme.tx2 : Color(hex: 0xC7D0DC)))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(primary ? Theme.accent : (ghost ? .clear : Color(hex: 0x171C25))))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(primary ? Theme.accent : (ghost ? .clear : Color(hex: 0x262D3A)),
                              lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == ConsoleButtonStyle {
    static var console: ConsoleButtonStyle { ConsoleButtonStyle() }
    static var consolePrimary: ConsoleButtonStyle { ConsoleButtonStyle(primary: true) }
    static var consoleGhost: ConsoleButtonStyle { ConsoleButtonStyle(ghost: true) }
}

/// A small square tile carrying a role's two-letter mark. The same colour follows a role
/// everywhere it appears, which is what lets a lane of agents be read without labels.
struct RoleTile: View {
    let role: String
    var size: CGFloat = 22

    var body: some View {
        Text(RoleTile.mark(role))
            .font(Typo.mono(size < 26 ? 9.5 : 11, .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size / 3).fill(color.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: size / 3)
                .strokeBorder(color.opacity(0.28), lineWidth: 1))
    }

    static func mark(_ role: String) -> String {
        let r = role.lowercased()
        if r.contains("frontend") { return "fe" }
        if r.contains("backend") { return "be" }
        if r.contains("qa") { return "qa" }
        if r.contains("sre") { return "sre" }
        if r.contains("fde") { return "fde" }
        if r.contains("product") { return "pr" }
        if r.contains("lead") { return "EL" }
        return String(r.prefix(2))
    }

    static func color(of role: String) -> Color {
        let r = role.lowercased()
        if r.contains("frontend") { return Theme.accent }
        if r.contains("backend") { return Theme.green }
        if r.contains("qa") { return Theme.violet }
        if r.contains("sre") || r.contains("fde") { return Theme.amber }
        return Theme.tx2
    }

    private var color: Color { RoleTile.color(of: role) }
}

/// The flat progress bar that sits under a project, a lane, or an agent.
struct MeterBar: View {
    let value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x1E242F))
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// A dot that says whether something is live, in the same colour language as everything
/// else. The ring is what separates "running right now" from a static status.
struct StateDot: View {
    var color: Color = Theme.accent
    var live = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay {
                if live {
                    Circle().strokeBorder(color.opacity(0.35), lineWidth: 1).padding(-4)
                }
            }
    }
}
