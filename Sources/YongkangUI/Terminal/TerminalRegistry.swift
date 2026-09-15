import AppKit
import Observation
import SwiftTerm
import YongkangCore

/// Owns every session's terminal, and so its process, for as long as the session is open.
/// Panes only borrow a terminal through `TerminalHost`, so leaving a project, switching
/// sections or laying the window out differently never touches a running agent. A process
/// ends when it exits by itself or when `terminate` is called for its session.
///
/// docs/architecture.md, "Terminal lifetime", has the SwiftTerm behaviour this relies on.
///
/// ponytail: a terminal no pane shows still parses its output on the main thread, as the hidden
/// ones in the old `opacity(0)` stack did. If many busy sessions ever show up in a profile, stop
/// feeding detached terminals and replay a bounded backlog when a pane borrows one.
@MainActor @Observable final class TerminalRegistry {
    /// Progress, or an instruction to pick by hand, while a session's CLI is being steered to a
    /// child agent's view. By session id.
    private(set) var childNavigation: [UUID: String] = [:]
    /// A session's process exited by itself. One that `terminate` ended isn't reported.
    @ObservationIgnored var onExit: (UUID) -> Void = { _ in }
    /// The question a session's terminal is asking the user changed; nil once it is answered.
    @ObservationIgnored var onAttention: (UUID, String?) -> Void = { _, _ in }

    @ObservationIgnored private var entries: [UUID: Entry] = [:]
    private let shell: [String]
    @ObservationIgnored private var keyMonitor: Any?

    /// ponytail: an interactive login shell by default, because a GUI app inherits a bare PATH
    /// and agent CLIs commonly live in ~/.local/bin or nvm paths exported from .zshrc.
    init(shell: [String] = ["/bin/zsh", "-ilc"]) {
        self.shell = shell
        // One monitor for every terminal: whichever has the keyboard notes what was typed, so a
        // queued message waits for the user's draft, and a key press stops steering its CLI.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            (event.window?.firstResponder as? AttentionTerminalView)?.recordInput(event)
            return event
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// The terminal a session runs in, for its pane to borrow. Nil once it is terminated.
    func view(for id: UUID) -> AttentionTerminalView? {
        entries[id]?.view
    }

    /// Runs the session's command line in a new PTY. Starting a session twice does nothing.
    func start(_ session: CodeSession) {
        guard entries[session.id] == nil else { return }
        // Non-zero frame matters: a 0x0 terminal starts the PTY at 0 columns and the TUI dies.
        // The first pane that shows it resizes it.
        let view = AttentionTerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        let entry = Entry(view: view, label: session.title, agent: session.agent)
        let id = session.id
        entry.onExit = { [weak self] in self?.onExit(id) }
        view.processDelegate = entry
        view.onAttention = { [weak self] reason in self?.onAttention(id, reason) }
        view.onCheck = { [weak self] in self?.typeQueued(id) }
        view.startProcess(
            executable: shell[0], args: Array(shell.dropFirst()) + [session.line],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true))
        entries[id] = entry
    }

    /// Types `text` into the session's CLI as one message and presses Enter: how a follow-up
    /// reaches an agent that is already working, instead of starting a competing one.
    ///
    /// It waits while something else has the terminal: a question only the user can answer, a
    /// draft they are typing, or a child agent's view. Then it is typed once, at the first
    /// check after the terminal's output that finds none of those in the way.
    func send(_ text: String, to id: UUID) {
        guard let entry = entries[id] else { return }
        entry.queued.append(text)
        typeQueued(id)
    }

    /// Ends the session's process and forgets its terminal.
    ///
    /// SwiftTerm's `terminate` stops watching the child before it has exited, so nothing else
    /// ever collects it: it is reaped here, off the main thread, or it stays a zombie until the
    /// app quits. For the same reason `onExit` never hears about it.
    func terminate(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        notice(nil, for: id)
        // SwiftTerm reaped a child that exited by itself, so its pid may be another process's now.
        guard !entry.exited else { return }
        let pid = entry.view.process.shellPid
        entry.view.terminate()
        guard pid > 0 else { return }  // waitpid(0) and kill(0) mean this whole process group.
        DispatchQueue.global(qos: .utility).async { TerminalRegistry.reap(pid) }
    }

    /// SIGTERM and the closed PTY end a CLI within a moment. One that ignores both for 5 s is
    /// killed, rather than left a zombie with a thread waiting on it forever.
    nonisolated private static func reap(_ pid: pid_t) {
        for _ in 0..<50 {
            guard waitpid(pid, nil, WNOHANG) == 0 else { return }
            usleep(100_000)
        }
        kill(pid, SIGKILL)
        waitpid(pid, nil, 0)
    }

    // MARK: - Typing

    private func typeQueued(_ id: UUID) {
        guard let entry = entries[id], !entry.queued.isEmpty else { return }
        let view = entry.view
        guard view.process.running else {
            entry.queued = []  // Nobody is left to read it.
            return
        }
        guard !entry.showsChild, !view.hasDraft, view.attentionReason == nil else { return }
        // ponytail: bracketed paste so embedded newlines land as one message instead of
        // submitting early, then a real Enter to send it — exactly what a paste followed
        // by Return looks like to the process. Untested against Claude Code's own reader;
        // if it does not honor bracketed paste this degrades to that same early-submit.
        for text in entry.queued { type("\u{1b}[200~" + text + "\u{1b}[201~\r", into: view) }
        entry.queued = []
    }

    private func type(_ text: String, into view: AttentionTerminalView) {
        view.process.send(data: Array(text.utf8)[...])
    }

    // MARK: - Child agents

    /// Steers the session's CLI to `child`'s live view, or back to the session's own for nil,
    /// by typing the CLI's picker command and moving down to the child's row. Called by the pane
    /// showing the session, and ends when the row is picked, the user types, or the pane's task
    /// is cancelled.
    func showChild(_ child: SubagentStatus?, in id: UUID) async {
        guard let entry = entries[id], entry.child != child?.id else { return }
        let view = entry.view
        while view.hasDraft {
            notice("Submit or clear the CLI draft before switching agents.", for: id)
            guard await tick(), entries[id] === entry else { return }
        }
        let wasChild = entry.child != nil
        entry.child = child?.id
        entry.showsChild = true
        notice(child == nil ? nil : "Opening child agent…", for: id)
        guard let childView = entry.agent?.provider.childView, view.process.running else {
            notice("This CLI cannot open a live child-agent view.", for: id)
            return
        }
        // A child view drawn over the conversation closes with Esc. One that took the
        // conversation over is left by picking the session's own row.
        if wasChild && childView.parentRow == nil { type("\u{1b}", into: view) }
        guard let target = child.map({ [$0.id, $0.description] }) ?? childView.parentRow.map({ [$0] }) else {
            entry.showsChild = false
            return
        }
        var interrupted = false
        view.onUserInput = { [weak self] in
            interrupted = true
            self?.notice(nil, for: id)
        }
        await pick(target, with: childView, in: entry, id: id) {
            interrupted
        }
    }

    /// Types the picker command, then walks its rows until the selected one names `target`.
    private func pick(
        _ target: [String], with childView: ChildView, in entry: Entry, id: UUID, interrupted: () -> Bool
    ) async {
        let view = entry.view
        var typedCommand = false
        var lastRow: String?
        var visited = Set<String>()
        // ponytail: CLI picker navigation uses rendered labels. If the CLI changes its
        // layout or truncates the identity, leave the picker open for manual selection.
        for _ in 0..<80 {
            guard await tick(), !interrupted(), entries[id] === entry else { return }
            guard view.process.running else { break }
            guard view.attentionReason == nil else { continue }
            guard typedCommand else {
                type("\u{1b}[200~" + childView.command + "\u{1b}[201~\r", into: view)
                typedCommand = true
                continue
            }
            let screen = view.screen
            guard let row = ChildAgentPicker.selectedRow(in: screen, of: childView) else {
                // Claude Code skips the picker when there is only one background task.
                if childView.parentRow == nil, screen.contains(target[0]), screen.lowercased().contains("esc") {
                    notice(nil, for: id)
                    return
                }
                continue
            }
            guard row != lastRow else { continue }
            lastRow = row
            if ChildAgentPicker.matches(row, identities: target) {
                type("\r", into: view)
                entry.showsChild = entry.child != nil
                notice(nil, for: id)
                return
            }
            guard visited.insert(row).inserted else {
                notice("Child not found in the CLI picker. Select it below if it is still available.", for: id)
                return
            }
            type("\u{1b}[B", into: view)
        }
        notice("Could not select this child automatically. Select it in the CLI picker below.", for: id)
    }

    /// Written only when it changes: each write re-renders the pane showing it, and every key
    /// the user types into a terminal clears it.
    private func notice(_ message: String?, for id: UUID) {
        if childNavigation[id] != message { childNavigation[id] = message }
    }

    /// A quarter second between looks at the screen. False once the pane has stopped asking.
    private func tick() async -> Bool {
        try? await Task.sleep(for: .milliseconds(250))
        return !Task.isCancelled
    }
}

/// One session's terminal and what the registry remembers about it. It is also the terminal's
/// `processDelegate`, which the view holds only weakly.
private final class Entry: LocalProcessTerminalViewDelegate {
    let view: AttentionTerminalView
    /// Named in the exit notice, so a dead process says which one it was.
    let label: String
    let agent: AgentKind?
    var onExit: () -> Void = {}
    /// Set once the child has exited by itself and SwiftTerm has reaped it.
    private(set) var exited = false
    /// Messages waiting for the terminal to be free.
    var queued: [String] = []
    /// The child agent the CLI was last steered to; nil for the session's own view.
    var child: String?
    /// While a child's view may be up, a message would reach the child instead, so it waits.
    var showsChild = false

    init(view: AttentionTerminalView, label: String, agent: AgentKind?) {
        self.view = view
        self.label = label
        self.agent = agent
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        exited = true
        let code = exitCode.map(String.init) ?? "?"
        source.feed(
            text: "\r\n\u{1b}[33m[\(label) exited (\(code)) — close the session and start it again]\u{1b}[0m\r\n")
        onExit()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

/// Only send selection keys inside a recognized CLI picker, never into a chat prompt.
enum ChildAgentPicker {
    static func selectedRow(in screen: String, of childView: ChildView) -> String? {
        let text = screen.replacingOccurrences(of: "\0", with: " ")
        guard childView.isPicker(text.lowercased()) else { return nil }
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("❯") || $0.hasPrefix("›") || $0.hasPrefix(">") }
    }

    static func matches(_ row: String, identities: [String]) -> Bool {
        identities.contains { identity in
            !identity.isEmpty
                && row.range(
                    of: "(?<![\\w-])" + NSRegularExpression.escapedPattern(for: identity)
                        + "(?![\\w-])", options: .regularExpression) != nil
        }
    }
}
