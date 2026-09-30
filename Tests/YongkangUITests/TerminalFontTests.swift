import AppKit
import Testing

@testable import YongkangUI

/// The terminals borrow the font of the user's iTerm default profile, so a prompt's Nerd Font
/// icons draw the same in both. Anything iTerm did not leave behind keeps SwiftTerm's own.
struct TerminalFontTests {
    private func defaults(_ profiles: [[String: Any]], default guid: String? = nil) -> UserDefaults {
        let suite = "TerminalFontTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(profiles, forKey: "New Bookmarks")
        if let guid { defaults.set(guid, forKey: "Default Bookmark Guid") }
        return defaults
    }

    @Test func theDefaultProfilesFontAndSize() throws {
        let font = try #require(
            TerminalFont.iTermFont(
                defaults(
                    [["Guid": "a", "Normal Font": "Courier 20"], ["Guid": "b", "Normal Font": "Menlo-Regular 13"]],
                    default: "b")))
        #expect(font.fontName == "Menlo-Regular")
        #expect(font.pointSize == 13)
    }

    @Test func noItermAMissingFontOrABadSpecIsNil() {
        #expect(TerminalFont.iTermFont(nil) == nil)
        #expect(TerminalFont.iTermFont(defaults([["Normal Font": "NoSuchFont-Regular 13"]])) == nil)
        #expect(TerminalFont.iTermFont(defaults([["Normal Font": "Menlo-Regular"]])) == nil)
    }
}
