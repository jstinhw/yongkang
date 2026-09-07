import Foundation

/// The lead's current plan, written beside its run records and refreshed by the app poll.
struct LeadCoordination: Equatable {
    var strategy = ""
    var parallelLimit: Int? = nil
    var estimatedTokens: Int? = nil
    var estimatedMinutes: Double? = nil
    var updatedAt: Date? = nil
    var contextSummary = ""
    var workers: [LeadWork] = []

    static func load(root: URL, session: CodeSession) -> LeadCoordination? {
        let notebook = root.resolvingSymlinksInPath().standardizedFileURL
        let runs = notebook.appendingPathComponent("runs").resolvingSymlinksInPath().standardizedFileURL
        guard runs.deletingLastPathComponent().path == notebook.path else { return nil }
        let prefix = session.id.uuidString.lowercased()
        let files = ((try? FileManager.default.contentsOfDirectory(at: runs,
                                                                 includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" && $0.lastPathComponent.lowercased().hasPrefix(prefix + "-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var plan: LeadCoordination?
        var workers: [LeadWork] = []
        var seen: Set<String> = []
        for file in files {
            guard file.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent().path == runs.path,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let fields = NotebookIndex.frontmatter(text)
            guard fields["kind"] == "run", fields["session"].flatMap(UUID.init(uuidString:)) == session.id
            else { continue }
            if file.lastPathComponent.lowercased() == prefix + "-coordination.md" {
                plan = LeadCoordination(strategy: fields["strategy"] ?? "",
                                        parallelLimit: count(fields["parallel_limit"], minimum: 1),
                                        estimatedTokens: count(fields["estimated_tokens"]),
                                        estimatedMinutes: minutes(fields["estimated_minutes"]),
                                        updatedAt: AgentUsage.date(fields["updated"]),
                                        contextSummary: fields["context_summary"] ?? "")
                continue
            }
            guard let id = fields["work_id"], safeID(id),
                  file.lastPathComponent.lowercased() == prefix + "-work-" + id.lowercased() + ".md",
                  let taskID = fields["task"], safeID(taskID),
                  session.taskIDs.isEmpty || session.taskIDs.contains(taskID),
                  seen.insert(id).inserted else { continue }
            let state = fields["status"] ?? "queued"
            let dependencies = NotebookIndex.list(fields["depends_on"] ?? "[]")
            guard ["queued", "running", "blocked", "review", "done", "failed"].contains(state),
                  dependencies.allSatisfy(safeID) else { continue }
            let started = AgentUsage.date(fields["started_at"])
            let finished = AgentUsage.date(fields["finished_at"]).flatMap { date -> Date? in
                if let started, date < started { return nil }
                return date
            }
            var work = LeadWork(id: id, taskID: taskID, title: nonempty(fields["title"]) ?? id,
                                skill: fields["skill"] ?? "", model: fields["model"] ?? "",
                                reason: fields["reason"] ?? "", dependsOn: dependencies, state: state,
                                agentID: nonempty(fields["agent_id"]),
                                estimatedTokens: count(fields["estimated_tokens"]),
                                estimatedMinutes: minutes(fields["estimated_minutes"]),
                                startedAt: started, finishedAt: finished,
                                updatedAt: AgentUsage.date(fields["updated"]),
                                actualTokens: count(fields["actual_tokens"]),
                                contextTokens: count(fields["context_tokens"]),
                                contextWindow: count(fields["context_window"], minimum: 1),
                                contextSource: fields["context_source"] ?? "",
                                checkpoint: fields["checkpoint"] ?? "",
                                report: fields["report"] ?? "")
            if state != "queued", started != nil, let subagent = work.subagent(in: session) {
                work.runtimeRunning = finished == nil && subagent.running && !session.exited
                // Reused threads contain other attempts. A returned attempt needs its end
                // timestamp before its transcript can be attributed safely.
                if let provider = session.agent, finished != nil || state == "running" || state == "blocked" {
                    let samples = AgentUsage.samples(at: subagent.transcriptURL, provider).filter { sample in
                        (started.map { sample.at > $0 } ?? true) && (finished.map { sample.at <= $0 } ?? true)
                    }
                    if !samples.isEmpty {
                        work.measuredTokens = samples.map(\.tally).reduce(TokenTally(), +).total
                        work.measuredModel = samples.last?.model
                        work.observedAt = samples.map(\.at).max()
                    }
                }
            }
            workers.append(work)
        }
        guard plan != nil || !workers.isEmpty else { return nil }
        var result = plan ?? LeadCoordination()
        result.workers = workers
        return result
    }

    private static func safeID(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0)
        }
    }

    private static func nonempty(_ text: String?) -> String? {
        text.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func count(_ text: String?, minimum: Int = 0) -> Int? {
        guard let text, let value = Int(text), value >= minimum else { return nil }
        return value
    }

    private static func minutes(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// A planned unit stays visible after its subagent returns; only the lead records QA-done.
struct LeadWork: Identifiable, Equatable {
    var id: String
    var taskID = ""
    var title = ""
    var skill = ""
    var model = ""
    var reason = ""
    var dependsOn: [String] = []
    var state = "queued"
    var agentID: String? = nil
    var estimatedTokens: Int? = nil
    var estimatedMinutes: Double? = nil
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    var updatedAt: Date? = nil
    var actualTokens: Int? = nil
    var contextTokens: Int? = nil
    var contextWindow: Int? = nil
    var contextSource = ""
    var checkpoint = ""
    var report = ""
    /// Observations stay separate from the lead's reported values and lifecycle state.
    var measuredTokens: Int? = nil
    var measuredModel: String? = nil
    var observedAt: Date? = nil
    var runtimeRunning: Bool? = nil

    var usedTokens: Int? { measuredTokens ?? actualTokens }
    var tokenSource: String { measuredTokens != nil ? "Measured" : actualTokens != nil ? "Reported" : "Unavailable" }

    func subagent(in session: CodeSession) -> SubagentStatus? {
        if let agentID { return session.subagents.first { $0.id == agentID } }
        // A task ID substring can name several workers. Only an exact work label is safe.
        let matches = session.subagents.filter { Subagents.normalize($0.description) == Subagents.normalize(id) }
        return matches.count == 1 ? matches.first : nil
    }

    /// Wall-clock elapsed from reported timestamps, never inferred from token throughput.
    func elapsedMinutes(now: Date = Date()) -> Double? {
        guard let startedAt else { return nil }
        let end = finishedAt ?? (state == "running" && runtimeRunning != false ? now : nil)
        guard let end, end >= startedAt else { return nil }
        return end.timeIntervalSince(startedAt) / 60
    }
}
