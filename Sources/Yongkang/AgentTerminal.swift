import SwiftTerm
import SwiftUI

enum AgentKind: String, CaseIterable, Identifiable {
    case claude
    case codex
    case grok
    case agy

    var id: Self { self }
    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok"
        case .agy: "Agy"
        }
    }
    var systemImage: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .grok: "bolt"
        case .agy: "a.circle"
        }
    }
    var command: String { rawValue }

    func skillInvocation(_ name: String, arguments: String) -> String {
        "\(self == .codex ? "$" : "/")\(name) \(arguments)"
    }

    /// Packaged sessions carry the app's exact skill text, so opening another project
    /// cannot silently pick a stale global skill or no skill at all. `instructions` keeps
    /// the pure branch testable; development builds fall back to native discovery.
    func skill(_ name: String, arguments: String, instructions: String? = nil) -> String {
        guard let instructions = instructions ?? BundledSkills.load(name) else {
            return skillInvocation(name, arguments: arguments)
        }
        return """
            Follow the bundled `\(name)` skill below. Treat `<arguments>` as `$ARGUMENTS`.

            <skill>
            \(instructions)
            </skill>

            <arguments>
            \(arguments)
            </arguments>
            """
    }
}

enum BundledSkills {
    /// The packaged `skills/` folder, or nil in a development build that has no Resources
    /// folder next to the binary.
    static var root: URL? {
        let executableResources = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        return [Bundle.main.resourceURL, executableResources].compactMap { $0 }
            .map { $0.appendingPathComponent("skills") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The packaged copy of one skill.
    static func url(_ name: String) -> URL? {
        guard let file = root?.appendingPathComponent("\(name)/SKILL.md"),
            FileManager.default.fileExists(atPath: file.path)
        else { return nil }
        return file
    }

    static func load(_ name: String) -> String? {
        url(name).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

enum AgentCommand {
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Each agent takes an opening prompt, which is how a new
    /// project's notebook conversation starts without anyone typing it.
    ///
    /// Claude Code and Grok accept `--session-id`; Codex gets a marker in its prompt so
    /// its rollout can be found later. Agy has neither and starts prompted sessions with
    /// `--prompt-interactive`.
    static func line(
        directory: String, agent: AgentKind, prompt: String?, sessionID: UUID? = nil,
        brief: Bool = false, noCommit: Bool = false
    ) -> String {
        let briefFlag = agent == .claude && brief ? "--brief " : ""
        let sessionFlag =
            agent == .claude || agent == .grok
            ? sessionID.map { "--session-id \($0.uuidString.lowercased()) " } ?? "" : ""
        let command = "\(agent.command) \(briefFlag)\(noCommit ? denyCommits(agent) : "")\(sessionFlag)"
            .trimmingCharacters(in: .whitespaces)
        let opening =
            agent == .codex
            ? prompt.flatMap { text in sessionID.map { "\(text)\n\n\(marker($0))" } } ?? prompt
            : prompt
        let promptFlag = agent == .agy && opening != nil ? " --prompt-interactive" : ""
        let start = opening.map { "exec \(command)\(promptFlag) \(quoted($0))" } ?? "exec \(command)"
        return "cd \(quoted(directory)) && \(start)"
    }

    /// Commits are the user's, made from the Review screen once they approve the work, so a
    /// lead session and its subagents are refused them outright rather than only asked in
    /// the skill. `=` keeps Claude's variadic flag from swallowing the prompt after it.
    /// ponytail: prefix rules, so `git -C . commit` slips past; the skill text covers that,
    /// and Codex and Agy have no deny flag at all.
    static func denyCommits(_ agent: AgentKind) -> String {
        let rules = ["Bash(git commit:*)", "Bash(git push:*)", "Bash(gh pr create:*)"]
        switch agent {
        case .claude: return "--disallowedTools=\(quoted(rules.joined(separator: ","))) "
        case .grok: return rules.map { "--deny \(quoted($0)) " }.joined()
        default: return ""
        }
    }

    /// Codex picks its own thread id, so `--session-id` has nothing to set on it: the only
    /// join from an app session row back to a rollout on disk is the opening prompt, which
    /// the rollout records verbatim. Every prompted Codex session therefore ends with its
    /// id, and `CodexTranscripts` finds the thread by looking for exactly this line —
    /// without it the app has a live terminal it cannot read a transcript from.
    static func marker(_ sessionID: UUID) -> String {
        "(Yongkang session \(sessionID.uuidString.lowercased()) — bookkeeping, not part of the task.)"
    }

    /// A service is whatever the repo starts with, so no `exec` — the command may be a
    /// pipeline or a shell function, and the login shell has to stay around to run it.
    static func line(directory: String, run command: String) -> String {
        "cd \(quoted(directory)) && \(command)"
    }
}

/// A real PTY running one shell line in the chosen directory.
struct AgentTerminal: NSViewRepresentable {
    let line: String
    /// Named in the exit notice, so a dead process says which one it was.
    let label: String
    /// Text queued to be typed into this session's already-running process, Enter and
    /// all — how a task reaches a lead that is already working instead of starting a
    /// competing one. Cleared once sent.
    @Binding var pending: String?
    /// Fired once, right when the process exits — the signal that this session can no
    /// longer be talked to.
    let onExit: () -> Void
    var onAttention: (String?) -> Void = { _ in }
    var focused = false
    var agent: AgentKind? = nil
    var child: SubagentStatus? = nil
    var onChildNavigation: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(label: label, onExit: onExit) }

    func makeNSView(context: Context) -> AttentionTerminalView {
        // Non-zero frame matters: a 0x0 terminal starts the PTY at 0 columns and the TUI dies.
        let view = AttentionTerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        view.processDelegate = context.coordinator
        view.onAttention = onAttention
        view.inputMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view] event in
            if let view, event.window === view.window, view.window?.firstResponder === view {
                view.recordInput(event)
            }
            return event
        }
        // ponytail: interactive login shell, because a GUI app inherits a bare PATH and
        // agent CLIs commonly live in ~/.local/bin or nvm paths exported from .zshrc.
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-ilc", line],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        )
        return view
    }

    func updateNSView(_ view: AttentionTerminalView, context: Context) {
        if focused != context.coordinator.focused {
            context.coordinator.focused = focused
            if focused {
                DispatchQueue.main.async { [weak view] in
                    guard let view else { return }
                    view.window?.makeFirstResponder(view)
                }
            }
        }
        if focused {
            context.coordinator.navigate(
                to: child, agent: agent, view: view,
                report: onChildNavigation)
        } else {
            context.coordinator.navigation?.invalidate()
        }
        // SwiftUI can call this more than once for the same state change (this terminal
        // becoming visible alongside `pending` being set triggers it from two directions
        // at once) — clearing `pending` is deferred to avoid mutating state mid-update, so
        // without this guard a fast second call would still see it set and send it twice.
        guard let text = pending, context.coordinator.canSendPending, !view.hasDraft, view.process.running,
            view.attentionReason == nil,
            !context.coordinator.sending
        else { return }
        context.coordinator.sending = true
        // ponytail: bracketed paste so embedded newlines land as one message instead of
        // submitting early, then a real Enter to send it — exactly what a paste followed
        // by Return looks like to the process. Untested against Claude Code's own reader;
        // if it does not honor bracketed paste this degrades to that same early-submit.
        let payload = "\u{1b}[200~" + text + "\u{1b}[201~\r"
        view.process.send(data: Array(payload.utf8)[...])
        DispatchQueue.main.async {
            pending = nil
            context.coordinator.sending = false
        }
    }

    static func dismantleNSView(_ view: AttentionTerminalView, coordinator: Coordinator) {
        coordinator.navigation?.invalidate()
        if let monitor = view.inputMonitor { NSEvent.removeMonitor(monitor) }
        view.terminate()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let label: String
        private let onExit: () -> Void
        /// Set while a queued `pending` send is in flight, so a repeat `updateNSView` call
        /// before the async clear lands does not send it a second time.
        var sending = false
        var focused = false

        var navigation: Timer?
        private var childID: String?
        var canSendPending = true

        func navigate(
            to child: SubagentStatus?, agent: AgentKind?, view: AttentionTerminalView,
            report: @escaping (String?) -> Void
        ) {
            guard childID != child?.id else { return }
            guard !view.hasDraft else {
                DispatchQueue.main.async { report("Submit or clear the CLI draft before switching agents.") }
                return
            }
            let wasChild = childID != nil
            childID = child?.id
            canSendPending = false
            navigation?.invalidate()
            DispatchQueue.main.async { report(child == nil ? nil : "Opening child agent…") }
            guard agent == .claude || agent == .codex, view.process.running else {
                DispatchQueue.main.async { report("This CLI cannot open a live child-agent view.") }
                return
            }
            // Claude's child view is an overlay; Codex switches the active conversation.
            if wasChild && agent == .claude { view.process.send(data: [27][...]) }
            guard child != nil || agent == .codex else {
                canSendPending = true
                return
            }
            let command = agent == .codex ? "/subagents" : "/tasks"
            let target = child.map { [$0.id, $0.description] } ?? ["Main [default]"]
            view.onUserInput = { [weak self] in
                self?.navigation?.invalidate()
                report(nil)
            }
            var ticks = 0
            var lastRow: String?
            var visited = Set<String>()
            // ponytail: CLI picker navigation uses rendered labels. If the CLI changes its
            // layout or truncates the identity, leave the picker open for manual selection.
            navigation = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak view] timer in
                guard let self, let view else {
                    timer.invalidate()
                    return
                }
                ticks += 1
                guard view.process.running, ticks < 80 else {
                    timer.invalidate()
                    report("Could not select this child automatically. Select it in the CLI picker below.")
                    return
                }
                guard view.attentionReason == nil else { return }
                if ticks == 1 {
                    view.process.send(data: Array(("\u{1b}[200~" + command + "\u{1b}[201~\r").utf8)[...])
                    return
                }
                let screen = view.screen
                guard let row = ChildAgentPicker.selectedRow(in: screen, agent: agent!) else {
                    // Claude skips the picker when there is only one background task.
                    if agent == .claude, let child,
                        screen.contains(child.id), screen.lowercased().contains("esc")
                    {
                        timer.invalidate()
                        report(nil)
                    }
                    return
                }
                guard row != lastRow else { return }
                lastRow = row
                if ChildAgentPicker.matches(row, identities: target) {
                    view.process.send(data: [13][...])
                    timer.invalidate()
                    self.canSendPending = child == nil
                    report(nil)
                } else if visited.insert(row).inserted {
                    view.process.send(data: Array("\u{1b}[B".utf8)[...])
                } else {
                    timer.invalidate()
                    report("Child not found in the CLI picker. Select it below if it is still available.")
                }
            }
        }

        init(label: String, onExit: @escaping () -> Void) {
            self.label = label
            self.onExit = onExit
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let code = exitCode.map(String.init) ?? "?"
            source.feed(
                text: "\r\n\u{1b}[33m[\(label) exited (\(code)) — close the session and start it again]\u{1b}[0m\r\n")
            onExit()
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}

/// Only send selection keys inside a recognized CLI picker, never into a chat prompt.
enum ChildAgentPicker {
    static func selectedRow(in screen: String, agent: AgentKind) -> String? {
        let text = screen.replacingOccurrences(of: "\0", with: " ")
        let lower = text.lowercased()
        let picker =
            agent == .claude
            ? lower.contains("background") && lower.contains("enter") && lower.contains("view")
            : lower.contains("agent") && lower.contains("enter")
                && (lower.contains("select") || lower.contains("confirm"))
        guard picker else { return nil }
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
