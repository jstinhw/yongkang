import Foundation

/// Agy (`agy`). It runs in its live terminal only: nothing it writes to disk is read.
package struct AgyProvider: AgentProvider {
    package init() {}

    package var kind: AgentKind { .agy }
    package var displayName: String { "Agy" }
    package var systemImage: String { "a.circle" }
    package var skillPrefix: String { "/" }

    /// No session id and no deny flag. A prompted session starts with `--prompt-interactive`.
    package func launch(prompt: String?, sessionID: UUID?, brief: Bool, noCommit: Bool) -> [String] {
        prompt.map { ["--prompt-interactive", AgentCommand.quoted($0)] } ?? []
    }

    package func ask(prompt: String) -> [String] {
        ["-p", AgentCommand.quoted(prompt)]
    }

    package func transcriptURL(session: UUID, project: URL) async -> URL? {
        nil
    }

    package func subagents(session: UUID, project: URL, taskIDs: [String]) async -> [SubagentStatus] {
        []
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        []
    }

    package func usage(at url: URL) async -> [UsageSample] {
        []
    }

    /// No consent screen of Agy's has been captured, so none raises a notice.
    package func attentionReason(screen: String) -> String? {
        nil
    }

    package var childView: ChildView? { nil }
}
