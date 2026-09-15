import Foundation

/// Claude Code (`claude`). `ClaudeTranscripts` reads its sessions off `~/.claude/projects/`,
/// the files `--resume` uses.
package struct ClaudeCodeProvider: AgentProvider {
    package static let shared = ClaudeCodeProvider()

    package init() {}

    package var kind: AgentKind { .claude }
    package var displayName: String { "Claude Code" }
    package var systemImage: String { "sparkles" }
    package var skillPrefix: String { "/" }

    /// `--session-id` names the transcript after the app's row. `=` keeps the variadic
    /// `--disallowedTools` from swallowing the prompt after it.
    package func launch(prompt: String?, sessionID: UUID?, brief: Bool, noCommit: Bool) -> [String] {
        let denied = AgentCommand.quoted(AgentCommand.commitRules.joined(separator: ","))
        let words: [String?] = [
            brief ? "--brief" : nil,
            noCommit ? "--disallowedTools=\(denied)" : nil,
            sessionID.map { "--session-id \($0.uuidString.lowercased())" },
            prompt.map(AgentCommand.quoted),
        ]
        return words.compactMap { $0 }
    }

    package func transcriptURL(session: UUID, project: URL) -> URL? {
        ClaudeTranscripts.transcriptURL(sessionID: session, projectDirectory: project)
    }

    package func subagents(session: UUID, project: URL, taskIDs: [String]) -> [SubagentStatus] {
        ClaudeTranscripts.subagents(sessionID: session, projectDirectory: project, taskIDs: taskIDs)
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        ClaudeTranscripts.transcript(at: url)
    }

    package func usage(at url: URL) -> [UsageSample] {
        AgentUsage.samples(at: url, .claude)
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
