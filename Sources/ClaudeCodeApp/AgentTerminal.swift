import SwiftUI
import SwiftTerm

enum AgentKind: String {
    case claude
    case codex

    var displayName: String { self == .claude ? "Claude Code" : "Codex" }
    var systemImage: String { self == .claude ? "sparkles" : "chevron.left.forwardslash.chevron.right" }
    var command: String { rawValue }
}

enum AgentCommand {
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Both agents take an opening prompt as their first argument, which is how a new
    /// project's notebook conversation starts without anyone typing it.
    static func line(directory: String, agent: AgentKind, prompt: String?) -> String {
        let start = prompt.map { "exec \(agent.command) \(quoted($0))" } ?? "exec \(agent.command)"
        return "cd \(quoted(directory)) && \(start)"
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

    func makeCoordinator() -> Coordinator { Coordinator(label: label) }

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

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        view.terminate()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let label: String

        init(label: String) {
            self.label = label
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let code = exitCode.map(String.init) ?? "?"
            source.feed(text: "\r\n\u{1b}[33m[\(label) exited (\(code)) — close the session and start it again]\u{1b}[0m\r\n")
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
