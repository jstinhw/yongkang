import Foundation

/// Codex (`codex`). `CodexTranscripts` reads its sessions off the rollouts under
/// `~/.codex/sessions/`, the files `codex resume` uses.
package struct CodexProvider: AgentProvider {
    package static let shared = CodexProvider()

    package init() {}

    package var kind: AgentKind { .codex }
    package var displayName: String { "Codex" }
    package var systemImage: String { "chevron.left.forwardslash.chevron.right" }
    package var skillPrefix: String { "$" }

    /// Only the prompt: Codex has no `--session-id`, no deny flag and no brief mode. A prompted
    /// session's id rides at the end of the prompt instead, as `marker`.
    package func launch(prompt: String?, sessionID: UUID?, brief: Bool, noCommit: Bool) -> [String] {
        prompt.map { text in [AgentCommand.quoted(sessionID.map { "\(text)\n\n\(Self.marker($0))" } ?? text)] } ?? []
    }

    /// Codex picks its own thread id, so `--session-id` has nothing to set on it: the only
    /// join from an app session row back to a rollout on disk is the opening prompt, which
    /// the rollout records verbatim. Every prompted Codex session therefore ends with its
    /// id, and `CodexTranscripts` finds the thread by looking for exactly this line —
    /// without it the app has a live terminal it cannot read a transcript from.
    static func marker(_ sessionID: UUID) -> String {
        "(Yongkang session \(sessionID.uuidString.lowercased()) — bookkeeping, not part of the task.)"
    }

    package func transcriptURL(session: UUID, project: URL) -> URL? {
        CodexTranscripts.transcriptURL(sessionID: session, projectDirectory: project)
    }

    package func subagents(session: UUID, project: URL, taskIDs: [String]) -> [SubagentStatus] {
        CodexTranscripts.subagents(sessionID: session, projectDirectory: project, taskIDs: taskIDs)
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        CodexTranscripts.transcript(at: url)
    }

    package func usage(at url: URL) -> [UsageSample] {
        AgentUsage.samples(at: url, .codex)
    }

    /// Captured in `Fixtures/codex/codex-0.154.0-trust-screen.ansi`.
    package func attentionReason(screen: String) -> String? {
        let text = AgentPrompt.visibleText(screen)
        guard text.contains("do you trust the contents of this directory?"), text.contains("yes, continue"),
            text.contains("no, quit")
        else { return nil }
        return "Codex needs you to decide whether to trust this directory."
    }

    /// `/subagents` switches the whole conversation to the child, so going back picks the
    /// main thread's row.
    package var childView: ChildView? {
        ChildView(command: "/subagents", parentRow: "Main [default]") { screen in
            screen.contains("agent") && screen.contains("enter")
                && (screen.contains("select") || screen.contains("confirm"))
        }
    }
}
