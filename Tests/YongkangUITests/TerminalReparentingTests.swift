import AppKit
import SwiftTerm
import SwiftUI
import Testing

@testable import YongkangUI

/// The spike behind D13 in docs/refactor-plan.md: a registry owns each session's terminal view,
/// and whichever pane is visible borrows it by re-parenting. These pin the SwiftTerm behaviour
/// that design relies on; docs/architecture.md, "Terminal lifetime", has the source lines.
///
/// Serialized because PTY output and the attention check arrive as jobs on the process-wide
/// main queue, and another main-actor test running in between would hold them up.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct TerminalReparentingTests {
    /// Counts forever, and reports its PTY size on every SIGWINCH, which is how a TUI learns
    /// it has to redraw.
    private static let ticker =
        "trap 'echo winch $(stty size)' WINCH; i=0; while :; do i=$((i+1)); echo tick $i; sleep 0.05; done"

    /// Draws a trust question for `ask`, and clears the screen to echo any other line.
    private static let responder = #"""
        while IFS= read -r line; do
          case "$line" in
            ask) printf '%s\r\n' 'Do you trust the contents of this directory?' '1. Yes, continue' '2. No, quit' ;;
            *) printf '\033[2J\033[Hgot:%s\r\n' "$line" ;;
          esac
        done
        """#

    // MARK: - Helpers

    /// Sized like `AgentTerminal` makes it: a 0x0 terminal starts the PTY at 0 columns.
    private func startTerminal(_ script: String) -> AttentionTerminalView {
        let view = AttentionTerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        view.startProcess(executable: "/bin/sh", args: ["-c", script])
        return view
    }

    /// `terminate()` cancels SwiftTerm's exit watcher before the child has exited, so nothing
    /// reaps it. Kill and reap it here, so no test leaves a process behind, even on failure.
    private func stop(_ view: AttentionTerminalView) {
        let pid = view.process.shellPid
        view.terminate()
        guard pid > 0 else { return }  // kill(0) would signal this whole process group.
        kill(pid, SIGKILL)
        waitpid(pid, nil, 0)
    }

    /// An offscreen window with a large and a small pane: two places in the work area that
    /// could show the same session.
    private func makeWindow() -> (window: NSWindow, large: NSView, small: NSView) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 600), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let large = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        let small = NSView(frame: CGRect(x: 800, y: 0, width: 400, height: 240))
        window.contentView?.addSubview(large)
        window.contentView?.addSubview(small)
        return (window, large, small)
    }

    /// Moves `terminal` into `container` and lays it out, the way `TerminalHost` does.
    private func attach(_ terminal: NSView, to container: NSView) {
        pin(terminal, into: container)
        container.layoutSubtreeIfNeeded()
        #expect(terminal.window != nil, "the pane is in a window")
    }

    /// Everything the terminal has been fed, scrollback included.
    private func lines(_ view: AttentionTerminalView) -> [String] {
        String(decoding: view.getTerminal().getBufferAsData(), as: UTF8.self)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func lastTick(_ view: AttentionTerminalView) -> Int {
        lines(view).compactMap { $0.hasPrefix("tick ") ? Int($0.dropFirst(5)) : nil }.max() ?? 0
    }

    /// True once the child's last SIGWINCH report matches the terminal's grid.
    private func childSeesTerminalSize(_ view: AttentionTerminalView) -> Bool {
        guard let report = lines(view).last(where: { $0.hasPrefix("winch ") }) else { return false }
        let terminal = view.getTerminal()
        return report == "winch \(terminal.rows) \(terminal.cols)"
    }

    private func isAlive(_ view: AttentionTerminalView) -> Bool {
        view.process.running && kill(view.process.shellPid, 0) == 0
    }

    /// Suspends between checks instead of pumping `RunLoop.main`: the test is itself a
    /// main-queue job, so a nested pump never runs the PTY reads queued behind it.
    ///
    /// ponytail: a generous bound, not a timing claim. Other suites run on the main actor in
    /// parallel (WorkflowTests' git calls hold it for seconds), so the PTY reads can queue for
    /// a while. Tighten it once git runs off the main thread (plan PR 4.1/4.2).
    private func eventually(within seconds: Double = 15, _ condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    // MARK: - AppKit

    @Test func detachedTerminalKeepsItsProcessAndReadsOutput() async throws {
        let (window, large, _) = makeWindow()
        defer { window.close() }
        let view = startTerminal(Self.ticker)
        defer { stop(view) }
        attach(view, to: large)
        #expect(view.window === window)
        #expect(try await eventually { lastTick(view) >= 3 })

        view.removeFromSuperview()
        #expect(view.window == nil)
        let atDetach = lastTick(view)
        #expect(
            try await eventually { lastTick(view) >= atDetach + 5 }, "output keeps reaching the buffer while detached")
        #expect(isAlive(view), "leaving the window must not stop the process")

        attach(view, to: large)
        #expect(lines(view).contains("tick \(atDetach + 5)"), "re-attaching shows what arrived meanwhile")
        let atAttach = lastTick(view)
        #expect(try await eventually { lastTick(view) > atAttach })
    }

    @Test func detachedTerminalDrainsAFloodWithoutBlockingTheChild() async throws {
        let (window, large, _) = makeWindow()
        defer { window.close() }
        // Far more than the kernel's PTY buffer holds, so the child only gets to `flood-done`
        // if its output is being read. Detached before the first suspension, so none of it is
        // read while the view is in the window.
        let view = startTerminal("seq 1 200000; echo flood-done; exec sleep 60")
        defer { stop(view) }
        attach(view, to: large)
        view.removeFromSuperview()

        #expect(try await eventually(within: 20) { lines(view).contains("flood-done") })
        #expect(view.window == nil)
    }

    @Test func reattachingIntoADifferentSizeResizesTheTerminalAndTheChild() async throws {
        let (window, large, small) = makeWindow()
        defer { window.close() }
        let view = startTerminal(Self.ticker)
        defer { stop(view) }
        // Wait for the loop, so the WINCH trap is set before the first resize.
        #expect(try await eventually { lastTick(view) >= 1 })
        attach(view, to: large)
        let terminal = view.getTerminal()
        let largeGrid = (rows: terminal.rows, cols: terminal.cols)
        #expect(try await eventually { childSeesTerminalSize(view) })

        view.removeFromSuperview()
        attach(view, to: small)
        #expect(view.frame.size == small.bounds.size)
        #expect(terminal.rows < largeGrid.rows && terminal.cols < largeGrid.cols)
        #expect(try await eventually { childSeesTerminalSize(view) }, "the child gets SIGWINCH and the new size")

        view.removeFromSuperview()
        attach(view, to: large)
        #expect(terminal.rows == largeGrid.rows && terminal.cols == largeGrid.cols)
        #expect(try await eventually { childSeesTerminalSize(view) })
    }

    @Test func reattachedTerminalTakesFocusAndTypedInput() async throws {
        let (window, large, small) = makeWindow()
        defer { window.close() }
        let view = startTerminal(Self.responder)
        defer { stop(view) }
        attach(view, to: large)
        window.makeFirstResponder(view)
        #expect(window.firstResponder === view)

        view.removeFromSuperview()
        #expect(window.firstResponder !== view, "AppKit takes focus from a view that leaves the window")
        attach(view, to: small)
        #expect(window.firstResponder !== view, "re-attaching doesn't restore focus by itself")

        // Check `firstResponder`, not the return value: `makeFirstResponder` also returns true
        // for a view that isn't in the window at all.
        window.makeFirstResponder(view)
        #expect(window.firstResponder === view)

        view.send(txt: "hello\r")
        #expect(try await eventually { lines(view).contains("got:hello") })

        let key = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "k",
                charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40))
        window.sendEvent(key)
        view.send(txt: "\r")
        #expect(try await eventually { lines(view).contains("got:k") }, "a key press reaches the process")
    }

    @Test func attentionSurvivesDetachAndReattach() async throws {
        let (window, large, small) = makeWindow()
        defer { window.close() }
        let view = startTerminal(Self.responder)
        defer { stop(view) }
        var notices: [String?] = []
        view.onAttention = { notices.append($0) }
        attach(view, to: large)

        view.removeFromSuperview()
        view.send(txt: "ask\r")
        #expect(try await eventually { notices.count == 1 }, "detection runs while detached")
        #expect(notices.first.flatMap { $0 } != nil)

        attach(view, to: small)
        try await Task.sleep(for: .milliseconds(400))
        #expect(view.attentionReason != nil, "the question is still on screen after re-attaching")
        #expect(notices.count == 1, "re-attaching and resizing doesn't repeat the notice")

        view.send(txt: "answered\r")
        #expect(try await eventually { notices.count == 2 })
        #expect(notices.last == .some(nil), "answering is still detected after re-attaching")
    }

    // MARK: - SwiftUI

    @Test func swiftUIHostBorrowsTheTerminalAcrossRemovalAndResize() async throws {
        let view = startTerminal(Self.ticker)
        defer { stop(view) }
        let grids = GridLog()
        view.processDelegate = grids
        let host = NSHostingView(rootView: Panes(slot: .large, terminal: view))
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        func show(_ slot: Slot) async throws {
            host.rootView = Panes(slot: slot, terminal: view)
            host.layoutSubtreeIfNeeded()
            let placed = try await eventually {
                slot.size.map { view.window === window && view.frame.size == $0 } ?? (view.superview == nil)
            }
            #expect(placed, "terminal placed for \(slot)")
        }

        try await show(.large)
        #expect(try await eventually { lastTick(view) >= 3 })
        let terminal = view.getTerminal()
        let largeGrid = (rows: terminal.rows, cols: terminal.cols)

        try await show(.none)
        let atRemoval = lastTick(view)
        #expect(try await eventually { lastTick(view) > atRemoval })
        #expect(isAlive(view), "dismantling the host must not stop the process")

        try await show(.small)
        #expect(terminal.rows < largeGrid.rows && terminal.cols < largeGrid.cols)
        #expect(try await eventually { childSeesTerminalSize(view) })

        // Straight from one pane to the other in a single update. SwiftUI makes the new host
        // before it dismantles the old one, so this fails if dismantling detaches blindly.
        try await show(.large)
        #expect(terminal.rows == largeGrid.rows && terminal.cols == largeGrid.cols)
        #expect(try await eventually { childSeesTerminalSize(view) })
        try await show(.small)
        #expect(isAlive(view))
        window.makeFirstResponder(view)
        #expect(window.firstResponder === view)

        // One PTY resize per insert into a different size (the first from the 900x560 the view
        // was made at), none on removal, and no transient sizes while SwiftUI lays out.
        #expect(grids.sizes.count == 4, "\(grids.sizes)")
    }
}

/// Pins `terminal` to `container`'s edges, taking it from wherever it was.
private func pin(_ terminal: NSView, into container: NSView) {
    terminal.removeFromSuperview()
    terminal.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(terminal)
    NSLayoutConstraint.activate([
        terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        terminal.topAnchor.constraint(equalTo: container.topAnchor),
        terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
}

/// The shape of PR 3.4's host: a plain container that borrows the registry's terminal.
private struct TerminalHost: NSViewRepresentable {
    let terminal: AttentionTerminalView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        pin(terminal, into: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    /// Lets go only of what this container still holds: in a move between panes the new host
    /// has already taken the terminal by the time the old one is dismantled.
    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        for view in container.subviews { view.removeFromSuperview() }
    }
}

/// Which pane the SwiftUI test shows the terminal in.
private enum Slot {
    case none
    case large
    case small

    var size: CGSize? {
        switch self {
        case .none: nil
        case .large: CGSize(width: 800, height: 500)
        case .small: CGSize(width: 400, height: 240)
        }
    }
}

private struct Panes: View {
    let slot: Slot
    let terminal: AttentionTerminalView

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            pane(.large)
            pane(.small)
        }
        .frame(width: 1200, height: 500, alignment: .topLeading)
    }

    @ViewBuilder private func pane(_ which: Slot) -> some View {
        let size = which.size ?? .zero
        if slot == which {
            TerminalHost(terminal: terminal).frame(width: size.width, height: size.height)
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }
}

/// Every grid size the terminal pushed to its PTY.
private final class GridLog: LocalProcessTerminalViewDelegate {
    private(set) var sizes: [String] = []

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        sizes.append("\(newRows)x\(newCols)")
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}
