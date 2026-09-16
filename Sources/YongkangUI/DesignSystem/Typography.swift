import AppKit
import SwiftUI

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
