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
    static let section = Typo.display(10)
}

/// The faces, and nothing else. Two of them, both the system's own: SF Pro for anything a
/// person reads, SF Mono for anything an agent typed — ids, paths, commands, diffs. They
/// come from `.system`, so there is no font to bundle, no name to look up, and no Mac where
/// the app quietly draws something else because a designer's font happened to be installed.
///
/// `display` and `text` are that same SF Pro; the default weight is the difference, which is
/// what a display size is for. Prefer `Typography`'s roles — this is the plumbing under them,
/// and `DesignTokenTests` fails the build if a screen reaches past a role to a raw size.
enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
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
                .font(Typography.section)
                .tracking(1.4)
                .foregroundStyle(Theme.tx3)
            if let trailing {
                Spacer(minLength: 8)
                Text(trailing).font(Typography.mono).foregroundStyle(Theme.tx3)
            }
        }
    }
}
