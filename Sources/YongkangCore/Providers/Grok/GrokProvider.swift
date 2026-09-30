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
    /// As `grok inspect` lists them in 1.0.30: it reads both other CLIs' folders as well as its own.
    ///
    /// ponytail: the folders only. Grok also finds skills nested inside those and in Claude Code
    /// plugins; list `grok inspect --json`'s `skills` instead if the page has to match it exactly.
    package var skillFolders: SkillFolders {
        SkillFolders(
            project: [".claude/skills", ".agents/skills"],
            home: [".grok/skills", ".claude/skills", ".agents/skills"])
    }

    /// `--session-id` like Claude Code; the commit rules are denied one `--deny` at a time.
    /// Grok takes a working directory and nothing beside it.
    package var readsOtherFolders: Bool { false }

    package func launch(prompt: String?, sessionID: UUID?, noCommit: Bool, reading: [String]) -> [String] {
        let denied = AgentCommand.commitRules.map { "--deny \(AgentCommand.quoted($0))" }
        let words: [String?] = [
            noCommit ? denied.joined(separator: " ") : nil,
            sessionID.map { "--session-id \($0.uuidString.lowercased())" },
            prompt.map(AgentCommand.quoted),
        ]
        return words.compactMap { $0 }
    }

    /// `--resume` by the id `--session-id` gave it, once the session has written its chat.
    package func resume(sessionID: UUID, project: URL, noCommit: Bool, reading: [String]) async -> [String]? {
        let transcript = GrokTranscripts.transcriptURL(sessionID: sessionID, projectDirectory: project)
        guard FileManager.default.fileExists(atPath: transcript.path) else { return nil }
        return launch(prompt: nil, sessionID: nil, noCommit: noCommit, reading: reading)
            + ["--resume \(sessionID.uuidString.lowercased())"]
    }

    package func ask(prompt: String) -> [String] {
        ["-p", AgentCommand.quoted(prompt)]
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

    /// 1.0.30 asks only in a folder with something of its own to load (an AGENTS.md, skills,
    /// hooks), so whether it would ask is its own call, which `grok inspect` gives. Through the
    /// login shell, as a session runs, so `grok` is on PATH.
    package func trusts(_ folder: URL) async -> Bool? {
        let line = AgentCommand.line(directory: folder.path, run: "exec grok inspect --json")
        guard let output = try? await AsyncProcess.run(URL(fileURLWithPath: "/bin/zsh"), ["-ilc", line]),
            output.status == 0
        else { return nil }
        return Self.projectTrusted(in: output.text)
    }

    /// Found by its key rather than by parsing the whole: a login shell may print before it.
    static func projectTrusted(in output: String) -> Bool? {
        guard let match = output.range(of: #""projectTrusted"\s*:\s*(true|false)"#, options: .regularExpression)
        else { return nil }
        return output[match].hasSuffix("true")
    }

    /// Captured in `Fixtures/grok/grok-1.0.30-trust-screen.ansi`. The question is Codex's word
    /// for word; the answers are not.
    package func attentionReason(screen: String) -> String? {
        let text = AgentPrompt.visibleText(screen)
        guard text.contains("do you trust the contents of this directory?"), text.contains("yes, proceed"),
            text.contains("no, quit")
        else { return nil }
        return "Grok needs you to decide whether to trust this directory."
    }

    package var childView: ChildView? { nil }
}
