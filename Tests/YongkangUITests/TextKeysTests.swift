import AppKit
import Testing

@testable import YongkangUI

/// ⌃W in a text box deletes the way a shell does, and nothing else is taken from anyone.
@Suite @MainActor struct TextKeysTests {
    /// The W key as the system reports it: ⌃W's characters are the control code, and only
    /// `charactersIgnoringModifiers` still says "w".
    private func key(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: flags.contains(.control) ? "\u{17}" : "w",
            charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
    }

    private func box(_ string: String, caret: Int? = nil, selecting: NSRange? = nil) -> NSTextView {
        let text = NSTextView()
        text.string = string
        text.setSelectedRange(selecting ?? NSRange(location: caret ?? (string as NSString).length, length: 0))
        return text
    }

    /// Return as the system reports it: the carriage return, whatever is held down with it.
    private func returnKey(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    }

    @Test func shiftReturnBreaksTheLineAtTheCaret() {
        let text = box("a CLI that", caret: 5)
        #expect(TextKeys.newline(returnKey(.shift), in: text), "the key is taken before anything selects the box")
        #expect(text.string == "a CLI\n that", "the line breaks where the caret was")
        #expect(!TextKeys.newline(returnKey([]), in: text), "plain Return still sends the prompt")
        #expect(
            !TextKeys.newline(returnKey([.shift, .command]), in: text),
            "a shortcut held with Shift is not a new line")
    }

    @Test func deletesBackToThePreviousSpaceLikeAShell() {
        let text = box("build from @designs/type/")
        #expect(TextKeys.handle(key(.control), in: text), "the key is taken")
        #expect(text.string == "build from ", "a path goes whole, not up to its last slash")
        _ = TextKeys.handle(key(.control), in: text)
        #expect(text.string == "build ", "the spaces before the caret go with the word")
    }

    @Test func deletesOnlyWhatIsBeforeTheCaretOrTheSelection() {
        let middle = box("one two three", caret: 7)
        _ = TextKeys.handle(key(.control), in: middle)
        #expect(middle.string == "one  three")

        let selected = box("one two three", selecting: NSRange(location: 4, length: 4))
        _ = TextKeys.handle(key(.control), in: selected)
        #expect(selected.string == "one three")
    }

    @Test func leavesEveryOtherKeyAndEveryOtherViewAlone() {
        let text = box("one two")
        #expect(!TextKeys.handle(key(.command), in: text), "⌘W closes the window")
        #expect(!TextKeys.handle(key([]), in: text), "w is typed")
        #expect(!TextKeys.handle(key([.control, .shift]), in: text))
        #expect(text.string == "one two")
        #expect(!TextKeys.handle(key(.control), in: NSView()), "a terminal sends its own ^W")
    }
}
