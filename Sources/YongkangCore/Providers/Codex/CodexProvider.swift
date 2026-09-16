import Foundation

/// Codex (`codex`). `CodexTranscripts` reads its sessions off the rollouts under
/// `~/.codex/sessions/`, the files `codex resume` uses.
package struct CodexProvider: AgentProvider {
    package static let shared = CodexProvider()

    private let transcripts = CodexTranscripts()
    private let usageReader = UsageReader { line, cursor in
        CodexProvider.sample(line, cursor: &cursor).map { [$0] } ?? []
    }

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

    /// `exec` refuses to run outside a git repository unless told to, and a question asked
    /// before a project exists is never inside one.
    package func ask(prompt: String) -> [String] {
        ["exec", "--skip-git-repo-check", AgentCommand.quoted(prompt)]
    }

    /// Codex picks its own thread id, so `--session-id` has nothing to set on it: the only
    /// join from an app session row back to a rollout on disk is the opening prompt, which
    /// the rollout records verbatim. Every prompted Codex session therefore ends with its
    /// id, and `CodexTranscripts` finds the thread by looking for exactly this line —
    /// without it the app has a live terminal it cannot read a transcript from.
    static func marker(_ sessionID: UUID) -> String {
        "(Yongkang session \(sessionID.uuidString.lowercased()) — bookkeeping, not part of the task.)"
    }

    package func transcriptURL(session: UUID, project: URL) async -> URL? {
        await transcripts.transcriptURL(sessionID: session, projectDirectory: project)
    }

    package func subagents(session: UUID, project: URL, taskIDs: [String]) async -> [SubagentStatus] {
        await transcripts.subagents(sessionID: session, projectDirectory: project, taskIDs: taskIDs)
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        CodexTranscripts.transcript(at: url)
    }

    package func usage(at url: URL) async -> [UsageSample] {
        await usageReader.samples(at: url)
    }

    /// Codex reports the session's running total on every turn instead of that turn's
    /// cost, so each sample is the difference from the last one. Differencing telescopes:
    /// the samples always add back up to the total the file last reported, which summing
    /// its `last_token_usage` fields does not — those repeat within a turn.
    private static func sample(_ line: String, cursor: inout UsageReader.Cursor) -> UsageSample? {
        guard let object = AgentUsage.json(line), let payload = object["payload"] as? [String: Any] else { return nil }
        // A turn names its model before it reports what the turn cost, and a session can
        // change model partway, so the latest one seen is the one a sample is filed under.
        if object["type"] as? String == "turn_context" {
            cursor.model = payload["model"] as? String ?? cursor.model
            return nil
        }
        guard payload["type"] as? String == "token_count",
            let at = AgentUsage.date(object["timestamp"] as? String),
            let info = payload["info"] as? [String: Any],
            let usage = info["total_token_usage"] as? [String: Any]
        else { return nil }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        // `input_tokens` is the whole prompt, cached part included, so the cached half is
        // subtracted out rather than counted twice.
        let cached = count("cached_input_tokens")
        let total = TokenTally(
            input: max(0, count("input_tokens") - cached),
            output: count("output_tokens"), cacheRead: cached,
            cacheWrite: count("cache_write_input_tokens"))
        let delta = total - cursor.running
        cursor.running = total
        return delta.total <= 0 ? nil : UsageSample(at: at, model: cursor.model, tally: delta)
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
