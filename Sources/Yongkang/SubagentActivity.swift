import Foundation

/// One subagent an agent session has spawned, read off its own transcript on disk —
/// Claude Code's `subagents/` folder or Codex's rollout tree, whichever this session is.
struct SubagentStatus: Identifiable, Equatable {
    let id: String
    let description: String
    let agentType: String
    let running: Bool
    let transcriptURL: URL
    /// The task this subagent was dispatched for, matched off its own label. Nil when the
    /// label names no task in the batch — a compaction or review subagent, or a lead that
    /// ignored the naming rule.
    var taskID: String? = nil
    /// The roster name of the team member whose skill this subagent runs, filled in when
    /// the session is read. Nil when the label names nobody on the team — a compaction or
    /// review agent, or a skill no team member owns.
    var member: String? = nil

    /// What to call it on screen: the person on the team, else the skill it runs.
    var displayName: String { member ?? agentType }

    /// The same subagent, told who on the team it is. Neither provider can do this: the
    /// roster is the project's, and a CLI knows only the label it was spawned under.
    ///
    /// The skill comes back with the name, and replaces whatever the provider called this
    /// thread — Codex nicknames a spawned thread ("Dewey", "Dirac"), and a nickname colours
    /// no tile, groups under nobody, and outlives the run in the ledger.
    func named(in team: [TeamMember]) -> SubagentStatus {
        guard let found = Team.running("\(description) \(agentType)", in: team) else { return self }
        return SubagentStatus(id: id, description: description, agentType: found.skill,
                              running: running, transcriptURL: transcriptURL, taskID: taskID,
                              member: found.member.name)
    }
}

/// The subagents attached to one assigned task, including an empty group while that task
/// waits for a dependency or for the lead to dispatch its first specialist.
struct SubagentTaskGroup: Identifiable {
    let id: String
    let subagents: [SubagentStatus]
}

/// One human-readable line pulled out of a subagent's transcript: the task it was given,
/// each tool it called, that tool's result, and its replies. Everything else in the file —
/// thinking blocks, bookkeeping fields — is left out rather than guessed at.
struct TranscriptLine: Identifiable {
    let id = UUID()
    let label: String
    let text: String
    /// Set on a tool result the provider marked as failed — the one thing a collapsed run
    /// of work still has to be able to say out loud.
    var isError = false
}

/// What both providers share: neither CLI records which notebook task a subagent is for,
/// so the link is the subagent's own label. The engineering-lead skill puts the task id in
/// every name it spawns; Claude keeps that as the Agent call's `description`, Codex slugs
/// it into `agent_path`, and normalizing both to the same shape matches them either way.
enum Subagents {
    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// Longest id first, so a label naming `edit-todo-api` is not claimed by `edit-todo`.
    static func taskID(in label: String, from taskIDs: [String]) -> String? {
        let haystack = normalize(label)
        return taskIDs.sorted { $0.count > $1.count }.first { haystack.contains(normalize($0)) }
    }

    static func grouped(_ subagents: [SubagentStatus], by taskIDs: [String]) -> [SubagentTaskGroup] {
        taskIDs.map { taskID in
            SubagentTaskGroup(id: taskID, subagents: subagents.filter { $0.taskID == taskID })
        }
    }

    static func runningTaskIDs(_ subagents: [SubagentStatus]) -> Set<String> {
        Set(subagents.compactMap { $0.running ? $0.taskID : nil })
    }
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
    /// swapping every "/" for "-". `claudeHome` is overridable so tests can point this at a
    /// throwaway root instead of the user's real `~/.claude`.
    static func projectFolder(
        projectDirectory: URL,
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    ) -> URL {
        claudeHome
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectDirectory.path.replacingOccurrences(of: "/", with: "-"),
                                    isDirectory: true)
    }

    /// A session's own folder inside it, keyed by its id — where its subagents are kept.
    static func sessionFolder(
        sessionID: UUID, projectDirectory: URL,
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    ) -> URL {
        projectFolder(projectDirectory: projectDirectory, claudeHome: claudeHome)
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    }

    /// The session's own transcript, beside that folder — what the reader watches a lead
    /// through, and what `subagents(...)` reads to tell a finished agent from a running one.
    ///
    /// Spelt out rather than derived by decorating `sessionFolder`: `appendingPathExtension`
    /// on a URL that points at a folder which exists keeps the folder's trailing slash, and
    /// the result is a directory URL that no longer equals the file it names.
    static func transcriptURL(
        sessionID: UUID, projectDirectory: URL,
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    ) -> URL {
        projectFolder(projectDirectory: projectDirectory, claudeHome: claudeHome)
            .appendingPathComponent(sessionID.uuidString.lowercased() + ".jsonl", isDirectory: false)
    }

    /// Foreground agents return their work in the first tool result. Background agents
    /// return an immediate launch receipt instead, then emit a task notification only
    /// when they stop. A later SendMessage resumes that same agent until it notifies again.
    static func isFinished(
        agentID: String, label: String, toolUseID: String, in transcript: String
    ) -> Bool {
        let lines = transcript.split(separator: "\n")
        guard let result = lines.firstIndex(where: { jsonField("tool_use_id", equals: toolUseID, in: $0) })
        else { return false }
        guard lines[result].contains("Async agent launched")
                || lines[result].contains("working in the background")
        else { return true }

        var finished = false
        let task = "<task-id>\(agentID)</task-id>"
        for line in lines[result...] {
            if line.contains(task)
                && ["completed", "failed", "killed"].contains(where: {
                    line.contains("<status>\($0)</status>")
                }) {
                finished = true
            } else if jsonField("name", equals: "SendMessage", in: line)
                        && ([agentID, label].contains(where: {
                            jsonField("recipient", equals: $0, in: line)
                                || jsonField("to", equals: $0, in: line)
                        })) {
                finished = false
            }
        }
        return finished
    }

    private static func jsonField(_ key: String, equals value: String, in line: Substring) -> Bool {
        line.contains("\"\(key)\":\"\(value)\"")
            || line.contains("\"\(key)\": \"\(value)\"")
    }

    /// Empty for a session with no `--session-id` match on disk yet — including every
    /// Codex or service-runner session, which never gets one.
    static func subagents(
        sessionID: UUID, projectDirectory: URL, taskIDs: [String] = [],
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
        let parent = transcriptURL(sessionID: sessionID, projectDirectory: projectDirectory,
                                   claudeHome: claudeHome)
        let transcript = (try? String(contentsOf: parent, encoding: .utf8)) ?? ""

        return metaFiles.compactMap { url -> SubagentStatus? in
            guard let data = try? Data(contentsOf: url),
                  let meta = try? JSONDecoder().decode(SubagentMeta.self, from: data) else { return nil }
            let agentID = String(url.lastPathComponent.dropFirst("agent-".count).dropLast(".meta.json".count))
            return SubagentStatus(id: agentID, description: meta.description, agentType: meta.agentType,
                                   running: !isFinished(agentID: agentID, label: meta.description,
                                                        toolUseID: meta.toolUseId, in: transcript),
                                   transcriptURL: subagentsDir.appendingPathComponent("agent-\(agentID).jsonl"),
                                   taskID: Subagents.taskID(in: meta.description, from: taskIDs))
        }.sorted { $0.description < $1.description }
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
            return TranscriptLine(label: "Result", text: truncate(resultText(block["content"])),
                                  isError: block["is_error"] as? Bool ?? false)
        default:
            return nil
        }
    }

    /// A `tool_result`'s content is either a plain string or a list of `{type, text}`
    /// blocks — this reads either shape rather than assuming one.
    static func resultText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let blocks = value as? [[String: Any]] {
            let texts = blocks.compactMap { $0["text"] as? String }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        return describe(value)
    }

    /// A one-line gist of an arbitrary JSON value — tool inputs carry whatever shape the
    /// tool defines, so this reads what it can instead of matching every one.
    static func describe(_ value: Any?) -> String {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        case let array as [Any]: return array.map(describe).joined(separator: ", ")
        case let dict as [String: Any]:
            return dict.sorted { $0.key < $1.key }.map { "\($0.key): \(describe($0.value))" }.joined(separator: ", ")
        default: return ""
        }
    }

    static func truncate(_ text: String) -> String {
        text.count > 500 ? String(text.prefix(500)) + "…" : text
    }
}
