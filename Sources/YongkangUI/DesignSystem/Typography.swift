import AppKit
import SwiftUI

/// What a piece of text *is*, rather than how big it is. A screen picks a role here and
/// gets whatever size and face that role currently means, so the scale moves in one place
/// instead of at every call site.
///
/// Six roles, each at the exact size its call sites already used — 5.1 renames, it does not
/// repaint, and `DesignTokenTests` holds them to it.
///
/// ponytail: this covers 142 of 376 call sites. The other 234 still spell a size out
/// through `Typo`, because the app's scale is a near-continuous 0.5 pt ramp — 32 spellings
/// across 15 sizes from 9 to 27 pt — and merging any two of them moves pixels, which 5.1
/// forbids. `grep -o 'Typo\.[a-z]*([0-9.]*' Sources` is the current list. 5.2's canvas is
/// where a real scale gets chosen and the ramp collapses into it.
enum Typography {
    /// A screen's subject: a card, a task, a review's verdict.
    static let title = Typo.display(22)
    /// A panel or section heading inside a screen.
    static let headline = Typo.display(15)
    /// Prose and row labels — the default for anything a person reads in sentences.
    static let body = Typo.text(12)
    /// The dimmer second line under a row: a subtitle, a count, a timestamp.
    static let caption = Typo.text(10.5)
    /// Anything an agent typed or a machine chose: ids, paths, commands, counts.
    static let mono = Typo.mono(10)
    /// Mono where it has to sit inside a row rather than own one.
    static let monoCaption = Typo.mono(9.5)
    /// The all-caps tracked label that heads every section on every screen.
    static let section = Typo.section
}

/// Three faces, each with one job: a display face for titles, a text face for prose, and a
/// mono for anything an agent typed — ids, paths, commands, diffs. Named faces are used
/// when they are installed and quietly fall back to the system stack when they are not, so
/// the app never ships a font it cannot draw.
///
/// The faces themselves. Prefer `Typography`'s roles; reach for these only for a size no
/// role carries yet.
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
                Text(trailing).font(Typography.mono).foregroundStyle(Theme.tx3)
            }
        }
    }
}
