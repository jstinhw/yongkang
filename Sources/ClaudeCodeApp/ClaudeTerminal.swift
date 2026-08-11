import SwiftUI
import SwiftTerm

/// A real PTY running `claude` in the chosen directory.
struct ClaudeTerminal: NSViewRepresentable {
    let directory: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // Non-zero frame matters: a 0x0 terminal starts the PTY at 0 columns and the TUI dies.
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        view.processDelegate = context.coordinator
        // ponytail: interactive login shell, because a GUI app inherits a bare PATH and
        // `claude` usually lives in ~/.local/bin or nvm — both only exported from .zshrc.
        let quoted = "'" + directory.replacingOccurrences(of: "'", with: "'\\''") + "'"
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-ilc", "cd \(quoted) && exec claude"],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        )
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let code = exitCode.map(String.init) ?? "?"
            source.feed(text: "\r\n\u{1b}[33m[claude exited (\(code)) — pick the folder again to restart]\u{1b}[0m\r\n")
        }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
