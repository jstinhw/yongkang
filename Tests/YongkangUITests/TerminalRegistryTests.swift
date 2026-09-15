import AppKit
import SwiftUI
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The registry is the only thing that ends a session's process: panes borrow its terminal,
/// typing goes through it, and closing a session or project terminates and reaps. Real
/// `/bin/sh` children in real PTYs, as in `TerminalReparentingTests`.
///
/// Serialized for the same reason as that suite: PTY output arrives as main-queue jobs.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct TerminalRegistryTests {
    private func registry() -> TerminalRegistry {
        TerminalRegistry(shell: ["/bin/sh", "-c"])
    }

    private func session(_ line: String, agent: AgentKind? = nil) -> CodeSession {
        CodeSession(title: "Test", icon: "terminal", line: line, agent: agent)
    }

    /// A CLI stand-in that appends every line it reads to `log`, and puts a trust question on
    /// screen when it reads `ask`.
    private func logger(_ log: URL) -> String {
        """
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> '\(log.path)'
          case "$line" in
            ask) printf '%s\\r\\n' 'Do you trust the contents of this directory?' '1. Yes, continue' '2. No, quit' ;;
            *) printf '\\033[2J\\033[Hgot it\\r\\n' ;;
          esac
        done
        """
    }

    private func lines(in log: URL) -> [String] {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// What `send` types for `text`, less the Enter, which the PTY turns into the line's end.
    private func paste(_ text: String) -> String {
        "\u{1b}[200~" + text + "\u{1b}[201~"
    }

    /// No process left with that id, not even a zombie: `kill(pid, 0)` still finds a zombie.
    private func isReaped(_ pid: pid_t) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }

    // MARK: - Lifetime

    @Test func aSessionKeepsItsProcessWhileItsPaneComesAndGoes() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let count = tmp.appendingPathComponent("count")
        let terminals = registry()
        let counter = session("while :; do echo x >> '\(count.path)'; sleep 0.05; done")
        terminals.start(counter)
        defer { terminals.terminate(counter.id) }
        let view = try #require(terminals.view(for: counter.id))
        let pid = view.process.shellPid

        let host = NSHostingView(rootView: SessionPane(terminal: view))
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func show(_ shown: Bool) {
            host.rootView = SessionPane(terminal: shown ? view : nil)
            host.layoutSubtreeIfNeeded()
        }

        show(true)
        #expect(
            try await eventually { view.window === window && view.frame.size == CGSize(width: 800, height: 460) },
            "the terminal fills the pane under its bar")
        show(false)
        #expect(try await eventually { view.superview == nil })
        let hidden = lines(in: count).count
        #expect(try await eventually { lines(in: count).count > hidden + 3 }, "the child keeps running with no pane")
        show(true)
        #expect(try await eventually { view.window === window })
        #expect(kill(pid, 0) == 0 && view.process.running && terminals.view(for: counter.id) === view)
    }

    @Test func terminatingEndsTheChildAndReapsIt() async throws {
        let terminals = registry()
        let sleeper = session("exec sleep 60")
        terminals.start(sleeper)
        let pid = try #require(terminals.view(for: sleeper.id)).process.shellPid
        try #require(pid > 0 && kill(pid, 0) == 0)

        terminals.terminate(sleeper.id)
        #expect(terminals.view(for: sleeper.id) == nil)
        #expect(try await eventually { isReaped(pid) }, "stopped and reaped, not left a zombie")
        #expect(waitpid(pid, nil, WNOHANG) == -1 && errno == ECHILD, "the registry already collected it")
    }

    @Test func closingASessionOrItsProjectEndsItsProcesses() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let model = AppModel(terminals: registry())
        let project = model.open(tmp)
        for title in ["Run web", "Run api", "Run docs"] {
            project.addSession(id: UUID(), title: title, icon: "play.circle", line: "exec sleep 60")
        }
        let pids = try project.sessions.map { try #require(model.terminals.view(for: $0.id)).process.shellPid }
        #expect(pids.allSatisfy { $0 > 0 && kill($0, 0) == 0 }, "adding a session to an open project starts it")

        model.close(project.sessions[0], in: project)
        #expect(try await eventually { isReaped(pids[0]) }, "closing a session ends its process")
        #expect(kill(pids[1], 0) == 0, "and only that one")

        let rest = project.sessions
        model.close(project)
        #expect(rest.allSatisfy { model.terminals.view(for: $0.id) == nil })
        #expect(try await eventually { pids.allSatisfy(isReaped) }, "closing the project ends the rest")
    }

    // MARK: - Typing

    @Test func aMessageWaitsForTheQuestionOnScreenAndIsTypedOnce() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("typed")
        let terminals = registry()
        let agent = session(logger(log))
        terminals.start(agent)
        defer { terminals.terminate(agent.id) }
        let view = try #require(terminals.view(for: agent.id))

        view.send(txt: "ask\r")
        #expect(try await eventually { view.attentionReason != nil })
        terminals.send("hello", to: agent.id)
        view.send(txt: "1\r")  // The user answers the question.
        #expect(try await eventually { lines(in: log).count == 3 })
        #expect(lines(in: log) == ["ask", "1", paste("hello")], "typed after the answer, not into the question")

        // Past the next check of the terminal after that output, so a message sent twice would
        // have gone again by now.
        try await Task.sleep(for: .milliseconds(500))
        terminals.send("bye", to: agent.id)
        #expect(try await eventually { lines(in: log).count >= 4 })
        #expect(lines(in: log) == ["ask", "1", paste("hello"), paste("bye")], "each message reaches the child once")
    }

    @Test func approvingADemoTypesOnlyTheApprovalIntoTheDesigner() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let directory = tmp.appendingPathComponent("app")
        _ = try NotebookFormat.create(.task, title: "Hero", in: NotebookFormat.root(in: directory), project: nil)
        let log = tmp.appendingPathComponent("typed")
        let model = AppModel(terminals: registry())
        let project = model.open(directory)
        defer { model.close(project) }
        let designer = UUID()
        project.addSession(id: designer, title: "Engineering Lead", icon: "sparkles", line: logger(log))
        let blocks = Blocks.root(in: project.notebookRoot)
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        let file = blocks.appendingPathComponent("hero-demo.md")
        try """
        ---
        id: hero-demo
        kind: demo
        title: "Hero"
        status: open
        session: \(designer.uuidString)
        ---

        ## Revisions

        - v1 · one claim, one button · http://localhost:3100
        """.write(to: file, atomically: true, encoding: .utf8)
        let demo = try #require(Blocks.block(at: file))
        model.enter(project)

        // What the demo page's approve button does: go where the workflow says, then reload.
        model.go(to: project.approveDemo(demo, revision: demo.revisions.last))
        model.reload()
        // PTY writes arrive in order, so anything the reload typed comes before this.
        model.terminals.send("end", to: designer)
        #expect(try await eventually { lines(in: log).last == paste("end") })
        let typed = lines(in: log)
        #expect(typed.count == 2, "\(typed)")
        #expect(
            typed.first?.contains("The demo at hero-demo is approved. Build v1.") == true,
            "the approval, and not the poll's Unblocked message as well")
    }

    // MARK: - Child agents

    /// Claude Code's background-task picker, drawn over the whole screen with `selected` marked.
    private func picker(selected: String) -> String {
        let rows = ["review-1-qa", "wire-auth-1-dev"].map { ($0 == selected ? "❯ " : "  ") + $0 }
        return "\u{1b}[2J\u{1b}[H"
            + (["Background tasks"] + rows + ["↑/↓ to select · Enter to view · Esc to close"])
            .joined(separator: "\r\n")
    }

    @Test func steeringToAChildTypesThePickerCommandAndWalksToItsRow() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("keys")
        let terminals = registry()
        // Records every key raw, and draws nothing: the test paints the screen itself.
        let lead = session("stty raw -echo; printf ready; exec cat > '\(log.path)'", agent: .claude)
        terminals.start(lead)
        defer { terminals.terminate(lead.id) }
        let view = try #require(terminals.view(for: lead.id))
        #expect(try await eventually { view.screen.contains("ready") })
        func keys() -> String { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }

        let child = SubagentStatus(
            id: "wire-auth-1-dev", description: "Wire auth", agentType: "dev", running: true, transcriptURL: tmp)
        let steering = Task { await terminals.showChild(child, in: lead.id) }
        #expect(try await eventually { keys() == paste("/tasks") + "\r" }, "the CLI's own picker command")
        #expect(terminals.childNavigation[lead.id] == "Opening child agent…")

        view.feed(text: picker(selected: "review-1-qa"))
        #expect(try await eventually { keys().hasSuffix("\u{1b}[B") }, "another child's row moves down")
        view.feed(text: picker(selected: "wire-auth-1-dev"))
        await steering.value
        #expect(keys() == paste("/tasks") + "\r" + "\u{1b}[B" + "\r", "Enter on the child's row, and nothing else")
        #expect(terminals.childNavigation[lead.id] == nil)

        await terminals.showChild(child, in: lead.id)
        #expect(keys().count == (paste("/tasks") + "\r\u{1b}[B\r").count, "a child already on screen is left alone")
    }
}

/// A work area: a bar, and the session's terminal filling the rest, or nothing.
private struct SessionPane: View {
    let terminal: AttentionTerminalView?

    var body: some View {
        VStack(spacing: 0) {
            Color.gray.frame(height: 40)
            if let terminal {
                TerminalHost(terminal: terminal)
            } else {
                Color.clear
            }
        }
        .frame(width: 800, height: 500)
    }
}
