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
}

/// A real PTY running the selected coding agent in the chosen directory.
struct AgentTerminal: NSViewRepresentable {
    let directory: String
    let agent: AgentKind
    let prompt: String?

    func makeCoordinator() -> Coordinator { Coordinator(agent: agent) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // Non-zero frame matters: a 0x0 terminal starts the PTY at 0 columns and the TUI dies.
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        view.processDelegate = context.coordinator
        // ponytail: interactive login shell, because a GUI app inherits a bare PATH and
        // agent CLIs commonly live in ~/.local/bin or nvm paths exported from .zshrc.
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-ilc", AgentCommand.line(directory: directory, agent: agent, prompt: prompt)],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        )
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        view.terminate()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let agent: AgentKind

        init(agent: AgentKind) {
            self.agent = agent
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let code = exitCode.map(String.init) ?? "?"
            source.feed(text: "\r\n\u{1b}[33m[\(agent.displayName) exited (\(code)) — pick the folder again to restart]\u{1b}[0m\r\n")
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
