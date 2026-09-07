import SwiftUI
import SwiftTerm

enum AgentKind: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: Self { self }
    var displayName: String { self == .claude ? "Claude Code" : "Codex" }
    var systemImage: String { self == .claude ? "sparkles" : "chevron.left.forwardslash.chevron.right" }
    var command: String { rawValue }

    func skillInvocation(_ name: String, arguments: String) -> String {
        "\(self == .claude ? "/" : "$")\(name) \(arguments)"
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
              FileManager.default.fileExists(atPath: file.path) else { return nil }
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

    /// Both agents take an opening prompt as their first argument, which is how a new
    /// project's notebook conversation starts without anyone typing it.
    ///
    /// `sessionID` only means anything to Claude Code — passing `--session-id` makes its
    /// transcript land at a path the app already knows, so it can go find that session's
    /// subagents later. Codex gets none: it picks its own id and never has a transcript
    /// the app goes looking for.
    static func line(directory: String, agent: AgentKind, prompt: String?, sessionID: UUID? = nil,
                     brief: Bool = false) -> String {
        let briefFlag = agent == .claude && brief ? "--brief " : ""
        let sessionFlag = agent == .claude
            ? sessionID.map { "--session-id \($0.uuidString.lowercased()) " } ?? "" : ""
        let command = "\(agent.command) \(briefFlag)\(sessionFlag)".trimmingCharacters(in: .whitespaces)
        let opening = agent == .codex
            ? prompt.flatMap { text in sessionID.map { "\(text)\n\n\(marker($0))" } } ?? prompt
            : prompt
        let start = opening.map { "exec \(command) \(quoted($0))" } ?? "exec \(command)"
        return "cd \(quoted(directory)) && \(start)"
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

    func makeCoordinator() -> Coordinator { Coordinator(label: label, onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // Non-zero frame matters: a 0x0 terminal starts the PTY at 0 columns and the TUI dies.
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        view.processDelegate = context.coordinator
        // ponytail: interactive login shell, because a GUI app inherits a bare PATH and
        // agent CLIs commonly live in ~/.local/bin or nvm paths exported from .zshrc.
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-ilc", line],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        )
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        // SwiftUI can call this more than once for the same state change (this terminal
        // becoming visible alongside `pending` being set triggers it from two directions
        // at once) — clearing `pending` is deferred to avoid mutating state mid-update, so
        // without this guard a fast second call would still see it set and send it twice.
        guard let text = pending, view.process.running, !context.coordinator.sending else { return }
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

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        view.terminate()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let label: String
        private let onExit: () -> Void
        /// Set while a queued `pending` send is in flight, so a repeat `updateNSView` call
        /// before the async clear lands does not send it a second time.
        var sending = false

        init(label: String, onExit: @escaping () -> Void) {
            self.label = label
            self.onExit = onExit
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let code = exitCode.map(String.init) ?? "?"
            source.feed(text: "\r\n\u{1b}[33m[\(label) exited (\(code)) — close the session and start it again]\u{1b}[0m\r\n")
            onExit()
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
