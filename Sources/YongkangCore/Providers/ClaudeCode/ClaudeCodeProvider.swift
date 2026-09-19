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
    package func launch(prompt: String?, sessionID: UUID?, noCommit: Bool) -> [String] {
        let denied = AgentCommand.quoted(AgentCommand.commitRules.joined(separator: ","))
        let words: [String?] = [
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

    package func attentionReason(screen: String) -> String? {
        let text = AgentPrompt.visibleText(screen)
        guard text.contains("do you trust the files in this folder?"), text.contains("yes"), text.contains("trust")
        else { return nil }
        return "Claude Code needs you to decide whether to trust this folder."
    }

    /// Background tasks, listed over the conversation.
    package var childView: ChildView? {
        ChildView(command: "/tasks", parentRow: nil) { screen in
            screen.contains("background") && screen.contains("enter") && screen.contains("view")
        }
    }
}
