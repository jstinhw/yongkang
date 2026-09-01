import Foundation

/// Reads a Codex session's subagents straight off the rollout files `codex resume` uses —
/// the same trade as `ClaudeTranscripts`: not a published API, so a storage-format change
/// upstream makes this read nothing rather than break anything the app depends on.
///
/// Codex picks its own thread id, so unlike Claude Code there is no `--session-id` to hand
/// it. The join is the prompt instead: every managed session's opening prompt carries this
/// app's session id, and the rollout records that prompt, so the thread that quotes it is
/// this row's thread. Its subagents are then every rollout whose parent chain reaches that
/// thread — read off disk instead of over the daemon socket, because the app already polls
/// files and a socket would be a second channel.
enum CodexTranscripts {
    /// One rollout's opening `session_meta` line, which never changes once written.
    private struct Meta {
        let threadID: String
        let parentThreadID: String?
        /// `/root/edit_todo_backend` → `edit_todo_backend`: the name the lead spawned it
        /// under, and the only place a subagent's own task is written down.
        let label: String
        let role: String
        let cwd: String
        let isSubagent: Bool
    }

    /// Parsed `session_meta` by path, and the resolved thread id by app session. Both are
    /// facts about a file's first line, so they are read once and kept.
    private static var metaCache: [String: Meta] = [:]
    private static var threadCache: [UUID: String] = [:]
    /// Sizes of rollouts already searched for a session id and not found, so a file is only
    /// re-read once it has grown — the prompt lands ~100KB in, well after the file appears.
    private static var searched: [String: UInt64] = [:]
    /// Only rollouts still being written can belong to a session this app started — a live
    /// session touches its rollout on every turn, a dead one never does. Purely a cost
    /// guard on the scan below, with slack for a session opened before the first poll: a
    /// stale rollout quotes some earlier run's session id and could never match anyway.
    /// A `var` so the self-test can wind it back over the fixtures it just wrote.
    static var launched = Date().addingTimeInterval(-300)

    static func subagents(
        sessionID: UUID, projectDirectory: URL, taskIDs: [String] = [],
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) -> [SubagentStatus] {
        let rollouts = rollouts(in: codexHome)
        guard let thread = thread(for: sessionID, in: projectDirectory, rollouts: rollouts) else { return [] }
        let entries = rollouts.compactMap { url in meta(at: url).map { (url, $0) } }
        let parents = Dictionary(entries.map { ($0.1.threadID, $0.1) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { url, meta -> SubagentStatus? in
            guard meta.isSubagent, isDescendant(meta, of: thread, in: parents) else { return nil }
            return SubagentStatus(id: meta.threadID, description: meta.label, agentType: meta.role,
                                  running: isRunning(url), transcriptURL: url,
                                  taskID: Subagents.taskID(in: meta.label, from: taskIDs))
        }.sorted { $0.description < $1.description }
    }

    private static func isDescendant(_ meta: Meta, of root: String, in threads: [String: Meta]) -> Bool {
        var parent = meta.parentThreadID
        var visited: Set<String> = []
        while let thread = parent, visited.insert(thread).inserted {
            if thread == root { return true }
            parent = threads[thread]?.parentThreadID
        }
        return false
    }

    /// The Codex thread this app session is driving. Cached once found: a PTY keeps its
    /// thread for life, and the scan below is the only expensive part of this file.
    private static func thread(for sessionID: UUID, in projectDirectory: URL, rollouts: [URL]) -> String? {
        if let known = threadCache[sessionID] { return known }
        let needle = sessionID.uuidString.lowercased()
        for url in rollouts {
            guard let meta = meta(at: url), !meta.isSubagent,
                  meta.cwd == projectDirectory.path, grew(url), quotes(needle, in: url) else { continue }
            threadCache[sessionID] = meta.threadID
            return meta.threadID
        }
        return nil
    }

    /// True the first time a file is seen and again every time it has grown since — a
    /// rollout that has not changed cannot have started quoting a session id it did not
    /// quote last time.
    private static func grew(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { UInt64($0) } ?? 0
        guard searched[url.path] != size else { return false }
        searched[url.path] = size
        return true
    }

    /// The prompt sits well into the file, behind the bundled skill text, so this reads a
    /// window rather than the line — and a window rather than the whole rollout, which
    /// grows without limit as the session works.
    private static func quotes(_ needle: String, in url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 512_000)) ?? Data()
        return String(decoding: head, as: UTF8.self).contains(needle)
    }

    /// Rollouts this app run could have started, newest first. The tree is `YYYY/MM/DD`, so
    /// the enumerator walks a handful of folders even on a machine with years of sessions.
    private static func rollouts(in codexHome: URL) -> [URL] {
        let root = codexHome.appendingPathComponent("sessions")
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles]) else { return [] }
        return walk.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return (values?.contentModificationDate ?? .distantPast) >= launched
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static func meta(at url: URL) -> Meta? {
        if let known = metaCache[url.path] { return known }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // The first line is `session_meta`; 256KB covers it with the base instructions it
        // carries, and reading a fixed window keeps a multi-megabyte rollout cheap.
        let head = String(decoding: (try? handle.read(upToCount: 256_000)) ?? Data(), as: UTF8.self)
        guard let line = head.split(separator: "\n", maxSplits: 1).first,
              let object = json(String(line)), let payload = object["payload"] as? [String: Any],
              let threadID = payload["id"] as? String ?? payload["session_id"] as? String,
              let cwd = payload["cwd"] as? String else { return nil }
        // `source` is a plain string for a session the user started and a nested object for
        // a spawned one — only the `thread_spawn` shape is a subagent with a task name on it.
        let spawn = ((payload["source"] as? [String: Any])?["subagent"] as? [String: Any])?["thread_spawn"]
            as? [String: Any]
        let path = spawn?["agent_path"] as? String
        let nickname = spawn?["agent_nickname"] as? String
        let meta = Meta(threadID: threadID,
                        parentThreadID: spawn?["parent_thread_id"] as? String
                            ?? payload["parent_thread_id"] as? String,
                        label: path.map { URL(fileURLWithPath: $0).lastPathComponent }
                            ?? nickname ?? String(threadID.prefix(8)),
                        role: spawn?["agent_role"] as? String ?? nickname ?? "subagent",
                        cwd: cwd, isSubagent: spawn != nil)
        metaCache[url.path] = meta
        return meta
    }

    /// A turn ends with `task_complete`, so whichever of the two markers is written last
    /// says whether this thread is still working — the same question `ClaudeTranscripts`
    /// answers with a `tool_use_id`, asked of a file that only ever grows at the end.
    static func isRunning(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 32_768
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        let done = tail.range(of: "\"task_complete\"", options: .backwards)
        guard let started = tail.range(of: "\"task_started\"", options: .backwards) else { return done == nil }
        guard let done else { return true }
        return started.lowerBound > done.lowerBound
    }

    /// The same four labels `ClaudeTranscripts` produces, off Codex's own line shapes.
    /// Only `response_item` lines are read: the `event_msg` lines beside them repeat the
    /// same assistant text, and everything else in the file is bookkeeping.
    static func transcript(at url: URL) -> [TranscriptLine] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line -> TranscriptLine? in
            guard let object = json(String(line)), object["type"] as? String == "response_item",
                  let payload = object["payload"] as? [String: Any] else { return nil }
            return transcriptLine(from: payload)
        }
    }

    private static func transcriptLine(from payload: [String: Any]) -> TranscriptLine? {
        switch payload["type"] as? String {
        case "message":
            // `developer` is the harness talking to the model — skills, environment, rules.
            let role = payload["role"] as? String ?? ""
            guard role == "user" || role == "assistant" else { return nil }
            let text = ClaudeTranscripts.resultText(payload["content"])
            guard !text.isEmpty else { return nil }
            // ponytail: a Codex subagent forks its parent's turns, so its opening user
            // message is the lead's whole prompt. Truncated, because the viewer is for
            // watching this subagent work, not for re-reading the batch it came from.
            return TranscriptLine(label: role == "assistant" ? "Reply" : "Task",
                                  text: role == "assistant" ? text : ClaudeTranscripts.truncate(text))
        case "agent_message":
            // The lead's dispatch. Its payload is encrypted, so what shows is the envelope:
            // the task name it was spawned under and who sent it.
            let text = ClaudeTranscripts.resultText(payload["content"])
            return text.isEmpty ? nil : TranscriptLine(label: "Task", text: ClaudeTranscripts.truncate(text))
        case "function_call", "custom_tool_call":
            let name = payload["name"] as? String ?? "tool"
            let input = ClaudeTranscripts.truncate(
                ClaudeTranscripts.describe(payload["arguments"] ?? payload["input"]))
            return TranscriptLine(label: "Tool", text: input.isEmpty ? name : "\(name)(\(input))")
        case "function_call_output", "custom_tool_call_output":
            return TranscriptLine(label: "Result",
                                  text: ClaudeTranscripts.truncate(ClaudeTranscripts.resultText(payload["output"])))
        default:
            return nil
        }
    }

    private static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
