import AppKit

/// ⌃W in every text box deletes back to the previous space, the way it does at a shell prompt
/// and in the agents' own input — the terminals one click away are where the key is learned.
/// The Cocoa text system binds ⌃W to `deleteToMark:`, which with no mark set does nothing a
/// person expects, and its own word deletion stops at `/`, so `@designs/type/` would go a
/// piece at a time.
///
/// A terminal is not an `NSTextView`, so its ⌃W still reaches the CLI untouched.
@MainActor enum TextKeys {
    /// Installed once, when the app starts, and never removed.
    static let monitor: Any? = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        handle(event, in: event.window?.firstResponder) ? nil : event
    }

    /// True when it was ⌃W in an editable text view, and the key is used up.
    static func handle(_ event: NSEvent, in responder: NSResponder?) -> Bool {
        guard let text = responder as? NSTextView, text.isEditable,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .control,
            event.charactersIgnoringModifiers == "w"
        else { return false }
        let caret = text.selectedRange()
        // A selection goes as a whole, as the shell's kill does with a region.
        let cut = caret.length > 0 ? caret : wordBefore(caret.location, in: text.string as NSString)
        // Through `insertText`, so the change is undoable and SwiftUI's binding hears it.
        if cut.length > 0 { text.insertText("", replacementRange: cut) }
        return true
    }

    /// Back over the spaces before `location`, then back to the next one: `unix-word-rubout`.
    static func wordBefore(_ location: Int, in string: NSString) -> NSRange {
        func isSpace(_ index: Int) -> Bool {
            UnicodeScalar(string.character(at: index)).map(CharacterSet.whitespacesAndNewlines.contains)
                ?? false
        }
        var start = location
        while start > 0, isSpace(start - 1) { start -= 1 }
        while start > 0, !isSpace(start - 1) { start -= 1 }
        return NSRange(location: start, length: location - start)
    }
}
