import SwiftUI

/// What a piece of text *is*, rather than how big it is. A screen picks a role here and
/// gets whatever size and face that role currently means, so the scale moves in one place
/// instead of at every call site.
///
/// Eight roles over seven sizes — `section` and `mono` both sit at 10 pt, in different
/// faces, because a tracked cap and an id are not the same thing. The app used to spell 15 sizes across a 0.5 pt ramp, which
/// is a ramp rather than a scale: nothing distinguished 11.5 pt from 12 pt except which file
/// you were in. A role that carries exactly one size is the thing that keeps a sixteenth from
/// appearing, and `DesignTokenTests` fails the build if a screen reaches past a role to spell
/// a size itself.
///
/// Where a call site leaned on weight rather than size — a row's own title against the text
/// beside it — the role takes the weight: `Typography.body(.semibold)`, never a new size.
enum Typography {
    /// A screen's subject: a card, a task, a review's verdict.
    static let title = Typo.display(22)

    /// A panel or section heading inside a screen.
    static let headline = Typo.display(15)

    /// Prose and row labels — the default for anything a person reads in sentences.
    static let body = Typo.text(12)
    /// `body` where a row's own title has to outweigh what sits beside it.
    static func body(_ weight: Font.Weight) -> Font { Typo.text(12, weight) }

    /// The dimmer second line under a row: a subtitle, a count, a timestamp.
    static let caption = Typo.text(10.5)
    /// `caption` where it labels rather than trails.
    static func caption(_ weight: Font.Weight) -> Font { Typo.text(10.5, weight) }

    /// Monospace that owns a pane: a diff, a transcript, a code block. Bigger than `mono`
    /// because a pane is read line after line, and 10 pt for that is a squint.
    static let code = Typo.mono(11.5)
    /// `code` for the one line in a pane that heads the rest: a file path, a hunk.
    static func code(_ weight: Font.Weight) -> Font { Typo.mono(11.5, weight) }

    /// Anything an agent typed or a machine chose, sitting inside a row rather than owning
    /// one: ids, paths, counts.
    static let mono = Typo.mono(10)
    /// `mono` where it is the row's subject rather than its trailing detail.
    static func mono(_ weight: Font.Weight) -> Font { Typo.mono(10, weight) }

    /// Mono small enough to sit beside `caption`, or inside a badge.
    static let monoCaption = Typo.mono(9.5)
    /// `monoCaption` in a badge, where a lighter weight would disappear at that size.
    static func monoCaption(_ weight: Font.Weight) -> Font { Typo.mono(9.5, weight) }

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
