import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// Serialized because the attention check is a work item on the process-wide main queue, and
/// its timing windows are tight: another main-actor test running in between can blur them.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AttentionPromptTests {
    private func makeView() -> AttentionTerminalView {
        AttentionTerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
    }

    /// The self-test pumped `RunLoop.main`, but a test already runs as a main-queue job, so a
    /// nested pump never drains the queue. Suspending frees it for the view's delayed check.
    private func pump(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    // Captured from Codex 0.154.0: the trust question is cursor-addressed word by
    // word, leaving empty terminal cells between words instead of ASCII spaces.
    @Test func detectsCapturedCodexTrustScreen() throws {
        let view = makeView()
        view.resize(cols: 100, rows: 30)
        let screen = try fixture("codex/codex-0.154.0-trust-screen.ansi")
        view.dataReceived(slice: Array(screen.utf8)[...])
        #expect(view.attentionReason != nil, "detect the actual cursor-addressed Codex trust screen")
    }

    // Each rendered capture, asked of each provider: a question is its own CLI's alone, even
    // Grok's, which is Codex's word for word with other answers. Claude Code 2.1.278 and Grok
    // lay their words out with cursor moves too.
    @Test(arguments: AgentKind.allCases)
    func onlyTheAskingCLIClaimsItsTrustScreen(kind: AgentKind) throws {
        let captures: [(file: String, asker: AgentKind)] = [
            ("codex/codex-0.154.0-trust-screen.ansi", .codex),
            ("claude/claude-2.1.278-trust-screen.ansi", .claude),
            ("grok/grok-1.0.30-trust-screen.ansi", .grok),
            ("agy/agy-1.2.4-trust-screen.ansi", .agy),
        ]
        for capture in captures {
            let view = makeView()
            view.resize(cols: 100, rows: 30)
            view.dataReceived(slice: Array(try fixture(capture.file).utf8)[...])
            #expect(
                (kind.provider.attentionReason(screen: view.screen) != nil) == (kind == capture.asker),
                "\(capture.file)")
        }
    }

    // The trust gate exists only in the PTY, before any rollout. Reproduce split,
    // ANSI-decorated writes in the same terminal renderer used by the live app.
    @Test func splitWritesRaiseAttentionOnceAndClearIt() async throws {
        let view = makeView()
        var notices: [String?] = []
        view.onAttention = { notices.append($0) }
        func output(_ text: String) { view.dataReceived(slice: Array(text.utf8)[...]) }

        output("\u{1b}[32mDo you trust the contents of this dire")
        #expect(view.attentionReason == nil)
        output("ctory?\u{1b}[0m\r\n1. Yes, continue\r\n2. No, quit\r\nPress enter to continue")
        #expect(view.attentionReason != nil, "trust prompts must be detected before transcripts exist")

        // Codex keeps emitting cursor/synchronized-update frames while awaiting input.
        // Detection must run during that stream, without waiting for it to go quiet.
        for _ in 0..<12 {
            output("\u{1b}[?2026h\u{1b}[?25h\u{1b}[?2026l")
            try await pump(50)
        }
        #expect(notices.count == 1, "notify while the trust screen is continuously redrawing")
        #expect(notices.first.flatMap { $0 } != nil, "notify while the trust screen is continuously redrawing")

        output("\r")
        try await pump(300)
        #expect(notices.count == 1, "repainting the same prompt must not repeat notifications")

        output("\u{1b}[2J\u{1b}[HWorking")
        try await pump(300)
        #expect(view.attentionReason == nil, "clear attention when the user answers and the gate disappears")
        #expect(notices.count == 2, "clear attention when the user answers and the gate disappears")
        #expect(notices.last == .some(nil), "clear attention when the user answers and the gate disappears")
    }

    @Test func mentionInOrdinaryOutputIsNotAPrompt() {
        #expect(AgentPrompt.reason(in: "Documentation: Do you trust the contents of this directory?") == nil)
    }

    // Exercise the real LocalProcess delegate path as well as direct renderer writes.
    @Test func realPTYRaisesAttention() async throws {
        let view = makeView()
        var notified = false
        view.onAttention = { notified = $0 != nil }
        view.startProcess(
            executable: "/bin/sh",
            args: [
                "-c",
                #"printf '%s\r\n' 'Do you trust the contents of this directory?' '1. Yes, continue' '2. No, quit'; while :; do printf '\033[?25h'; sleep 0.05; done"#,
            ])
        defer { view.terminate() }
        // ponytail: polls up to 5 s where the self-test slept a fixed 1 s, so a machine busy
        // with parallel tests doesn't flake. Raise the ceiling if a slow CI still misses it.
        let deadline = Date().addingTimeInterval(5)
        while !notified && Date() < deadline { try await pump(50) }
        #expect(notified, "a real PTY must raise attention while the trust gate keeps redrawing")
    }
}
