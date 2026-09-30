import AppKit

/// The font the terminals draw in: the one the user's iTerm default profile uses, when iTerm
/// is set up, else SwiftTerm's own.
///
/// A prompt themed for a Nerd Font (Powerlevel10k, Starship) draws its icons — the Apple logo,
/// the git branch, the clock — from the font's private-use glyphs, which no system font has.
/// In the system monospace those came out as boxes while the same shell in iTerm drew them.
/// Emoji were never the problem: Core Text falls back to Apple Color Emoji by itself.
///
/// ponytail: iTerm only, the terminal this app's users come from. Another terminal's font
/// (Ghostty's config, Terminal's profile) is one more reader here.
enum TerminalFont {
    /// Read once: a change in iTerm's settings shows in the next launch's terminals.
    @MainActor static let preferred: NSFont? = iTermFont(UserDefaults(suiteName: "com.googlecode.iterm2"))

    /// The default profile's "Normal Font", which iTerm keeps as the PostScript name and the
    /// size in one string: "MesloLGS-NF-Regular 13". Nil for anything that is not a font here.
    static func iTermFont(_ defaults: UserDefaults?) -> NSFont? {
        guard let profiles = defaults?.array(forKey: "New Bookmarks") as? [[String: Any]] else { return nil }
        let guid = defaults?.string(forKey: "Default Bookmark Guid")
        let profile = profiles.first { $0["Guid"] as? String == guid } ?? profiles.first
        guard let spec = profile?["Normal Font"] as? String,
            let space = spec.lastIndex(of: " "),
            let size = Double(spec[spec.index(after: space)...]), size > 0
        else { return nil }
        return NSFont(name: String(spec[..<space]), size: size)
    }
}
