import Foundation

/// Claude Code (`claude`). `ClaudeTranscripts` reads its sessions off `~/.claude/projects/`,
/// the files `--resume` uses.
package struct ClaudeCodeProvider: AgentProvider {
    package static let shared = ClaudeCodeProvider()

    private let usageReader = UsageReader { line, _ in ClaudeCodeProvider.sample(line).map { [$0] } ?? [] }

    package init() {}

    package var kind: AgentKind { .claude }
    package var displayName: String { "Claude Code" }
    package var systemImage: String { "sparkles" }
    package var skillPrefix: String { "/" }

    /// `--session-id` names the transcript after the app's row. `=` keeps the variadic
    /// `--disallowedTools` from swallowing the prompt after it.
    package var readsOtherFolders: Bool { true }

    package func launch(prompt: String?, sessionID: UUID?, noCommit: Bool, reading: [String]) -> [String] {
        let denied = AgentCommand.quoted(AgentCommand.commitRules.joined(separator: ","))
        // `--add-dir` takes every word after it up to the next flag, so it goes first, where
        // the flags behind it end it. After the prompt it would swallow the prompt as a folder.
        let folders = reading.map { "--add-dir \(AgentCommand.quoted($0))" }
        let words: [String?] =
            folders + [
                noCommit ? "--disallowedTools=\(denied)" : nil,
                sessionID.map { "--session-id \($0.uuidString.lowercased())" },
                prompt.map(AgentCommand.quoted),
            ]
        return words.compactMap { $0 }
    }

    package func ask(prompt: String) -> [String] {
        ["-p", AgentCommand.quoted(prompt)]
    }

    package func transcriptURL(session: UUID, project: URL) async -> URL? {
        ClaudeTranscripts.transcriptURL(sessionID: session, projectDirectory: project)
    }

    package func subagents(session: UUID, project: URL, taskIDs: [String]) async -> [SubagentStatus] {
        ClaudeTranscripts.subagents(sessionID: session, projectDirectory: project, taskIDs: taskIDs)
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        ClaudeTranscripts.transcript(at: url)
    }

    package func usage(at url: URL) async -> [UsageSample] {
        await usageReader.samples(at: url)
    }

    /// Claude Code stamps every assistant message with its model and what that message
    /// cost, so the file is already a ledger of deltas — one line, one sample.
    private static func sample(_ line: String) -> UsageSample? {
        guard line.contains("\"usage\""), let object = AgentUsage.json(line),
            let at = AgentUsage.date(object["timestamp"] as? String),
            let message = object["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let tally = TokenTally(
            input: count("input_tokens"), output: count("output_tokens"),
            cacheRead: count("cache_read_input_tokens"),
            cacheWrite: count("cache_creation_input_tokens"))
        return tally.total == 0
            ? nil
            : UsageSample(at: at, model: message["model"] as? String ?? "unknown", tally: tally)
    }

    package func trusts(_ folder: URL) async -> Bool? {
        Self.trusts(folder, config: TrustedFolder.home(".claude.json"))
    }

    /// 2.1.278 keeps the answer in `~/.claude.json`, under the folder's own path
    /// (`TrustedFolder.path`), and not under its repo's root or a parent's.
    static func trusts(_ folder: URL, config: URL) -> Bool? {
        guard let object = TrustedFolder.json(at: config) else { return nil }
        let entry = (object["projects"] as? [String: Any])?[TrustedFolder.path(of: folder)] as? [String: Any]
        return entry?["hasTrustDialogAccepted"] as? Bool == true
    }

    /// The question's wording changes between versions, but the choice that answers it has
    /// kept its words. 2.1.278's screen is `Fixtures/claude/claude-2.1.278-trust-screen.ansi`.
    package func attentionReason(screen: String) -> String? {
        let text = AgentPrompt.visibleText(screen)
        let asks =
            text.contains("do you trust the files in this folder?")
            || text.contains("is this a project you created or one you trust?")
        guard asks, text.contains("yes, i trust this folder") else { return nil }
        return "Claude Code needs you to decide whether to trust this folder."
    }

    /// Background tasks, listed over the conversation.
    package var childView: ChildView? {
        ChildView(command: "/tasks", parentRow: nil) { screen in
            screen.contains("background") && screen.contains("enter") && screen.contains("view")
        }
    }
}
