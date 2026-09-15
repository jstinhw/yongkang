import AppKit
import SwiftUI

/// Shows a running terminal wherever its pane is. It only borrows the view, which belongs to
/// `TerminalRegistry`, so taking the pane away never ends the process behind it.
///
/// docs/architecture.md, "Terminal lifetime", has the SwiftTerm behaviour each step relies on.
struct TerminalHost: NSViewRepresentable {
    let terminal: AttentionTerminalView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        Self.pin(terminal, into: container)
        // Not in a window until SwiftUI has placed the container, and `makeFirstResponder`
        // says yes to a view outside the window without doing anything.
        DispatchQueue.main.async { [weak terminal] in
            guard let terminal else { return }
            terminal.window?.makeFirstResponder(terminal)
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    /// Lets go only of what this container still holds: when a terminal moves between panes,
    /// SwiftUI makes the new host before it dismantles the old one, and by then the new one
    /// has already taken the terminal. Never terminates: the registry does that.
    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        for view in container.subviews { view.removeFromSuperview() }
    }

    /// Takes `terminal` from wherever it was and pins it to `container`'s edges. Constraints
    /// rather than a frame, so the terminal is resized once, straight to the pane's size: a
    /// tiny transient size would reflow its buffer and tell the child it is 2x1.
    static func pin(_ terminal: NSView, into container: NSView) {
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
