import Foundation

/// Grok (`grok`). `GrokTranscripts` reads the session it keeps under `~/.grok/sessions/` for
/// the id it was started with.
package struct GrokProvider: AgentProvider {
    package static let shared = GrokProvider()

    private let usageReader = UsageReader { line, _ in GrokProvider.samples(line) }

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

    package func transcriptURL(session: UUID, project: URL) async -> URL? {
        GrokTranscripts.transcriptURL(sessionID: session, projectDirectory: project)
    }

    /// Grok writes usage to its own stream beside the chat.
    package func usageURL(session: UUID, project: URL) async -> URL? {
        GrokTranscripts.usageURL(sessionID: session, projectDirectory: project)
    }

    /// Grok's subagents aren't read.
    package func subagents(session: UUID, project: URL, taskIDs: [String]) async -> [SubagentStatus] {
        []
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        GrokTranscripts.transcript(at: url)
    }

    package func usage(at url: URL) async -> [UsageSample] {
        await usageReader.samples(at: url)
    }

    /// Grok writes one completed-turn update with a per-model usage breakdown. Its input
    /// total includes cache reads, so subtract that part before putting it in our additive
    /// tally, the same way Codex's running total is handled.
    private static func samples(_ line: String) -> [UsageSample] {
        guard let object = AgentUsage.json(line),
            let timestamp = (object["timestamp"] as? NSNumber)?.doubleValue,
            let params = object["params"] as? [String: Any],
            let update = params["update"] as? [String: Any],
            update["sessionUpdate"] as? String == "turn_completed",
            let usage = update["usage"] as? [String: Any]
        else { return [] }
        let at = Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)

        func sample(_ model: String, _ value: [String: Any]) -> UsageSample? {
            func count(_ key: String) -> Int { (value[key] as? NSNumber)?.intValue ?? 0 }
            let cached = count("cachedReadTokens")
            let tally = TokenTally(
                input: max(0, count("inputTokens") - cached),
                output: count("outputTokens"), cacheRead: cached,
                cacheWrite: count("cacheCreationTokens"))
            return tally.total == 0 ? nil : UsageSample(at: at, model: model, tally: tally)
        }

        let models = usage["modelUsage"] as? [String: Any] ?? [:]
        let split = models.compactMap { model, value in sample(model, value as? [String: Any] ?? [:]) }
        return split.isEmpty ? sample("grok", usage).map { [$0] } ?? [] : split
    }

    /// No consent screen of Grok's has been captured, so none raises a notice.
    package func attentionReason(screen: String) -> String? {
        nil
    }

    package var childView: ChildView? { nil }
}
