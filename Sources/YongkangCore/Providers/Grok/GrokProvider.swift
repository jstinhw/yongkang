import Foundation

/// Grok (`grok`). `GrokTranscripts` reads the session it keeps under `~/.grok/sessions/` for
/// the id it was started with.
package struct GrokProvider: AgentProvider {
    package static let shared = GrokProvider()

    package init() {}

    package var kind: AgentKind { .grok }
    package var displayName: String { "Grok" }
    package var systemImage: String { "bolt" }
    package var skillPrefix: String { "/" }

    /// `--session-id` like Claude Code; the commit rules are denied one `--deny` at a time.
    package func launch(prompt: String?, sessionID: UUID?, brief: Bool, noCommit: Bool) -> [String] {
        let denied = AgentCommand.commitRules.map { "--deny \(AgentCommand.quoted($0))" }
        let words: [String?] = [
            noCommit ? denied.joined(separator: " ") : nil,
            sessionID.map { "--session-id \($0.uuidString.lowercased())" },
            prompt.map(AgentCommand.quoted),
        ]
        return words.compactMap { $0 }
    }

    package func transcriptURL(session: UUID, project: URL) -> URL? {
        GrokTranscripts.transcriptURL(sessionID: session, projectDirectory: project)
    }

    /// Grok writes usage to its own stream beside the chat.
    package func usageURL(session: UUID, project: URL) -> URL? {
        GrokTranscripts.usageURL(sessionID: session, projectDirectory: project)
    }

    /// Grok's subagents aren't read.
    package func subagents(session: UUID, project: URL, taskIDs: [String]) -> [SubagentStatus] {
        []
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        GrokTranscripts.transcript(at: url)
    }

    package func usage(at url: URL) -> [UsageSample] {
        AgentUsage.samples(at: url, .grok)
    }

    /// No consent screen of Grok's has been captured, so none raises a notice.
    package func attentionReason(screen: String) -> String? {
        nil
    }

    package var childView: ChildView? { nil }
}
