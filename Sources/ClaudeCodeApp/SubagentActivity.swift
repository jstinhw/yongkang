import Foundation

/// One subagent a Claude Code session has spawned, read off its own transcript on disk.
struct SubagentStatus: Identifiable, Equatable {
    let id: String
    let description: String
    let agentType: String
    let running: Bool
    let transcriptURL: URL
}

/// Reads a Claude Code session's subagents straight off the same on-disk transcripts
/// `--resume` uses. This is not a published API — a storage-format change upstream just
/// makes this read nothing, rather than break anything the app depends on.
enum ClaudeTranscripts {
    private struct SubagentMeta: Decodable {
        let agentType: String
        let description: String
        let toolUseId: String
    }

    /// Claude Code slugs a project's absolute path into its transcript folder name by
    /// swapping every "/" for "-", then keys each session's own folder by its id.
    /// `claudeHome` is overridable so tests can point this at a throwaway root instead of
    /// the user's real `~/.claude`.
    static func sessionFolder(
        sessionID: UUID, projectDirectory: URL,
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    ) -> URL {
        let slug = projectDirectory.path.replacingOccurrences(of: "/", with: "-")
        return claudeHome
            .appendingPathComponent("projects")
            .appendingPathComponent(slug)
            .appendingPathComponent(sessionID.uuidString.lowercased())
    }

    /// A `tool_use_id` shows up in a transcript exactly once, as the key on its
    /// `tool_result` — a substring check is enough, and far cheaper than parsing every
    /// line as JSON on every 2-second poll.
    static func isFinished(_ toolUseID: String, in transcript: String) -> Bool {
        transcript.contains("\"tool_use_id\":\"\(toolUseID)\"")
            || transcript.contains("\"tool_use_id\": \"\(toolUseID)\"")
    }

    /// Empty for a session with no `--session-id` match on disk yet — including every
    /// Codex or service-runner session, which never gets one.
    static func subagents(
        sessionID: UUID, projectDirectory: URL,
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    ) -> [SubagentStatus] {
        let folder = sessionFolder(sessionID: sessionID, projectDirectory: projectDirectory, claudeHome: claudeHome)
        let subagentsDir = folder.appendingPathComponent("subagents")
        let metaFiles = ((try? FileManager.default.contentsOfDirectory(
            at: subagentsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".meta.json") }
        guard !metaFiles.isEmpty else { return [] }
        // The parent's own transcript, read once and reused for every subagent below —
        // it says which of them already have a result.
        let transcript = (try? String(contentsOf: folder.appendingPathExtension("jsonl"), encoding: .utf8)) ?? ""

        return metaFiles.compactMap { url -> SubagentStatus? in
            guard let data = try? Data(contentsOf: url),
                  let meta = try? JSONDecoder().decode(SubagentMeta.self, from: data) else { return nil }
            let agentID = String(url.lastPathComponent.dropFirst("agent-".count).dropLast(".meta.json".count))
            return SubagentStatus(id: agentID, description: meta.description, agentType: meta.agentType,
                                   running: !isFinished(meta.toolUseId, in: transcript),
                                   transcriptURL: subagentsDir.appendingPathComponent("agent-\(agentID).jsonl"))
        }.sorted { $0.description < $1.description }
    }

    /// One human-readable line pulled out of a subagent's own transcript: the task it was
    /// given, each tool it called, that tool's result, and its replies. Everything else in
    /// the file — thinking blocks, bookkeeping fields — is left out rather than guessed at.
    struct TranscriptLine: Identifiable {
        let id = UUID()
        let label: String
        let text: String
    }

    static func transcript(at url: URL) -> [TranscriptLine] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").flatMap { line -> [TranscriptLine] in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["message"] as? [String: Any] else { return [] }
            let role = message["role"] as? String ?? ""
            let blocks: [[String: Any]]
            if let array = message["content"] as? [[String: Any]] {
                blocks = array
            } else if let plain = message["content"] as? String {
                blocks = [["type": "text", "text": plain]]
            } else {
                blocks = []
            }
            return blocks.compactMap { transcriptLine(from: $0, role: role) }
        }
    }

    private static func transcriptLine(from block: [String: Any], role: String) -> TranscriptLine? {
        switch block["type"] as? String {
        case "text":
            guard let text = block["text"] as? String, !text.isEmpty else { return nil }
            return TranscriptLine(label: role == "assistant" ? "Reply" : "Task", text: text)
        case "tool_use":
            let name = block["name"] as? String ?? "tool"
            let input = truncate(describe(block["input"]))
            return TranscriptLine(label: "Tool", text: input.isEmpty ? name : "\(name)(\(input))")
        case "tool_result":
            return TranscriptLine(label: "Result", text: truncate(resultText(block["content"])))
        default:
            return nil
        }
    }

    /// A `tool_result`'s content is either a plain string or a list of `{type, text}`
    /// blocks — this reads either shape rather than assuming one.
    private static func resultText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let blocks = value as? [[String: Any]] {
            let texts = blocks.compactMap { $0["text"] as? String }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        return describe(value)
    }

    /// A one-line gist of an arbitrary JSON value — tool inputs carry whatever shape the
    /// tool defines, so this reads what it can instead of matching every one.
    private static func describe(_ value: Any?) -> String {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        case let array as [Any]: return array.map(describe).joined(separator: ", ")
        case let dict as [String: Any]:
            return dict.sorted { $0.key < $1.key }.map { "\($0.key): \(describe($0.value))" }.joined(separator: ", ")
        default: return ""
        }
    }

    private static func truncate(_ text: String) -> String {
        text.count > 500 ? String(text.prefix(500)) + "…" : text
    }
}
