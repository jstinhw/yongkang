import Foundation

/// The lead's current plan, written beside its run records and refreshed by the app poll.
package struct LeadCoordination: Equatable {
    package var strategy = ""
    package var parallelLimit: Int? = nil
    package var estimatedTokens: Int? = nil
    package var estimatedMinutes: Double? = nil
    package var updatedAt: Date? = nil
    package var contextSummary = ""
    package var workers: [LeadWork] = []

    package init(
        strategy: String = "",
        parallelLimit: Int? = nil,
        estimatedTokens: Int? = nil,
        estimatedMinutes: Double? = nil,
        updatedAt: Date? = nil,
        contextSummary: String = "",
        workers: [LeadWork] = []
    ) {
        self.strategy = strategy
        self.parallelLimit = parallelLimit
        self.estimatedTokens = estimatedTokens
        self.estimatedMinutes = estimatedMinutes
        self.updatedAt = updatedAt
        self.contextSummary = contextSummary
        self.workers = workers
    }

    package static func load(root: URL, session: CodeSession) async -> LeadCoordination? {
        guard var result = read(root: root, only: session.id)[session.id] else { return nil }
        var workers: [LeadWork] = []
        for work in result.workers where session.taskIDs.isEmpty || session.taskIDs.contains(work.taskID) {
            workers.append(await observed(work, in: session))
        }
        result.workers = workers
        guard !result.workers.isEmpty || result != LeadCoordination() else { return nil }
        return result
    }

    /// Every lead's records on disk, by session id. Review reads these rather than the
    /// sessions open right now: a relaunch or a closed lead must not erase work that is
    /// still waiting for the user's approval.
    package static func all(root: URL) -> [UUID: LeadCoordination] { read(root: root, only: nil) }

    private static func read(root: URL, only: UUID?) -> [UUID: LeadCoordination] {
        let notebook = root.resolvingSymlinksInPath().standardizedFileURL
        let runs = notebook.appendingPathComponent("runs").resolvingSymlinksInPath().standardizedFileURL
        guard runs.deletingLastPathComponent().path == notebook.path else { return [:] }
        let prefix = only.map { $0.uuidString.lowercased() + "-" }
        let files =
            ((try? FileManager.default.contentsOfDirectory(
                at: runs,
                includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" && prefix.map($0.lastPathComponent.lowercased().hasPrefix) ?? true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var plans: [UUID: LeadCoordination] = [:]
        var seen: Set<String> = []
        for file in files {
            guard file.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent().path == runs.path,
                let text = try? String(contentsOf: file, encoding: .utf8)
            else { continue }
            let fields = NotebookIndex.frontmatter(text)
            guard fields["kind"] == "run", let session = fields["session"].flatMap(UUID.init(uuidString:)),
                only == nil || only == session
            else { continue }
            let name = file.lastPathComponent.lowercased()
            let own = session.uuidString.lowercased()
            if name == own + "-coordination.md" {
                var plan = plans[session] ?? LeadCoordination()
                plan.strategy = fields["strategy"] ?? ""
                plan.parallelLimit = count(fields["parallel_limit"], minimum: 1)
                plan.estimatedTokens = count(fields["estimated_tokens"])
                plan.estimatedMinutes = minutes(fields["estimated_minutes"])
                plan.updatedAt = AgentUsage.date(fields["updated"])
                plan.contextSummary = fields["context_summary"] ?? ""
                plans[session] = plan
                continue
            }
            guard let work = work(fields, text: text), name == own + "-work-" + work.id.lowercased() + ".md",
                seen.insert(own + work.id).inserted
            else { continue }
            plans[session, default: LeadCoordination()].workers.append(work)
        }
        return plans
    }

    /// One work record's frontmatter and body, or nil when it is malformed or could point
    /// outside the project.
    private static func work(_ fields: [String: String], text: String) -> LeadWork? {
        guard let id = fields["work_id"], safeID(id), let taskID = fields["task"], safeID(taskID) else { return nil }
        let state = fields["status"] ?? "queued"
        let dependencies = NotebookIndex.list(fields["depends_on"] ?? "[]")
        guard ["queued", "running", "blocked", "review", "done", "failed"].contains(state),
            dependencies.allSatisfy(safeID)
        else { return nil }
        let started = AgentUsage.date(fields["started_at"])
        let finished = AgentUsage.date(fields["finished_at"]).flatMap { date -> Date? in
            if let started, date < started { return nil }
            return date
        }
        // What this worker owned, as it reported it. Anything that could point outside
        // the project is dropped rather than shown against the wrong file.
        return LeadWork(
            id: id, taskID: taskID, title: nonempty(fields["title"]) ?? id,
            skill: fields["skill"] ?? "", model: fields["model"] ?? "",
            reason: fields["reason"] ?? "", dependsOn: dependencies,
            paths: NotebookIndex.list(fields["paths"] ?? "[]").compactMap(safePath),
            state: state,
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
            report: fields["report"] ?? "",
            result: section("Result", of: text),
            changeRequest: section("Change request", of: text))
    }

    /// What the live session adds to a record: whether its subagent is still running, and
    /// the tokens its transcript measured for this attempt.
    private static func observed(_ work: LeadWork, in session: CodeSession) async -> LeadWork {
        var work = work
        guard work.state != "queued", let started = work.startedAt, let subagent = work.subagent(in: session)
        else { return work }
        let finished = work.finishedAt
        work.runtimeRunning = finished == nil && subagent.running && !session.exited
        // Reused threads contain other attempts. A returned attempt needs its end
        // timestamp before its transcript can be attributed safely.
        if let kind = session.agent, finished != nil || work.state == "running" || work.state == "blocked" {
            let samples = await kind.provider.usage(at: subagent.transcriptURL).filter { sample in
                sample.at > started && (finished.map { sample.at <= $0 } ?? true)
            }
            if !samples.isEmpty {
                work.measuredTokens = samples.map(\.tally).reduce(TokenTally(), +).total
                work.measuredModel = samples.last?.model
                work.observedAt = samples.map(\.at).max()
            }
        }
        return work
    }

    /// The Markdown under one `## ` heading of a work record, up to the next one — where a
    /// worker writes what it did and the lead quotes what the user asked for, which is what
    /// the review page reads instead of a one-line summary.
    static func section(_ heading: String, of text: String) -> String {
        var lines: [String] = []
        var inside = false
        for line in NotebookIndex.body(text).components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if inside { break }
                inside = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == heading.lowercased()
            } else if inside {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func safeID(_ text: String) -> Bool {
        !text.isEmpty
            && text.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains(
                    $0)
            }
    }

    /// A repo-relative path and nothing else: no absolute paths, no `..`, no `~`. The
    /// leading `./` an agent sometimes writes is dropped so it still matches git's answer.
    private static func safePath(_ text: String) -> String? {
        var path = text.trimmingCharacters(in: .whitespaces)
        while path.hasPrefix("./") { path = String(path.dropFirst(2)) }
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
            !path.split(separator: "/").contains("..")
        else { return nil }
        return path
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
package struct LeadWork: Identifiable, Equatable {
    package var id: String
    package var taskID = ""
    package var title = ""
    package var skill = ""
    package var model = ""
    package var reason = ""
    package var dependsOn: [String] = []
    /// The files this worker reported owning, repo-relative. Empty when the lead did not
    /// record any — the summary then leaves this work's task without a diff of its own
    /// rather than guessing which files were its doing.
    package var paths: [String] = []
    package var state = "queued"
    var agentID: String? = nil
    package var estimatedTokens: Int? = nil
    package var estimatedMinutes: Double? = nil
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    package var updatedAt: Date? = nil
    var actualTokens: Int? = nil
    package var contextTokens: Int? = nil
    package var contextWindow: Int? = nil
    package var contextSource = ""
    package var checkpoint = ""
    package var report = ""
    /// The body's `## Result`: what the worker says it did, or QA's verdict and evidence.
    package var result = ""
    /// The body's `## Change request`: the user's comments the lead quoted for this attempt.
    package var changeRequest = ""
    /// Observations stay separate from the lead's reported values and lifecycle state.
    var measuredTokens: Int? = nil
    package var measuredModel: String? = nil
    var observedAt: Date? = nil
    package var runtimeRunning: Bool? = nil

    package init(
        id: String,
        taskID: String = "",
        title: String = "",
        skill: String = "",
        model: String = "",
        reason: String = "",
        dependsOn: [String] = [],
        paths: [String] = [],
        state: String = "queued",
        agentID: String? = nil,
        estimatedTokens: Int? = nil,
        estimatedMinutes: Double? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        updatedAt: Date? = nil,
        actualTokens: Int? = nil,
        contextTokens: Int? = nil,
        contextWindow: Int? = nil,
        contextSource: String = "",
        checkpoint: String = "",
        report: String = "",
        result: String = "",
        changeRequest: String = "",
        measuredTokens: Int? = nil,
        measuredModel: String? = nil,
        observedAt: Date? = nil,
        runtimeRunning: Bool? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.skill = skill
        self.model = model
        self.reason = reason
        self.dependsOn = dependsOn
        self.paths = paths
        self.state = state
        self.agentID = agentID
        self.estimatedTokens = estimatedTokens
        self.estimatedMinutes = estimatedMinutes
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
        self.actualTokens = actualTokens
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.contextSource = contextSource
        self.checkpoint = checkpoint
        self.report = report
        self.result = result
        self.changeRequest = changeRequest
        self.measuredTokens = measuredTokens
        self.measuredModel = measuredModel
        self.observedAt = observedAt
        self.runtimeRunning = runtimeRunning
    }

    package var usedTokens: Int? { measuredTokens ?? actualTokens }
    package var tokenSource: String {
        measuredTokens != nil ? "Measured" : actualTokens != nil ? "Reported" : "Unavailable"
    }

    package func subagent(in session: CodeSession) -> SubagentStatus? {
        if let agentID { return session.subagents.first { $0.id == agentID } }
        // A task ID substring can name several workers. Only an exact work label is safe.
        let matches = session.subagents.filter { Subagents.normalize($0.description) == Subagents.normalize(id) }
        return matches.count == 1 ? matches.first : nil
    }

    /// Wall-clock elapsed from reported timestamps, never inferred from token throughput.
    package func elapsedMinutes(now: Date = Date()) -> Double? {
        guard let startedAt else { return nil }
        let end = finishedAt ?? (state == "running" && runtimeRunning != false ? now : nil)
        guard let end, end >= startedAt else { return nil }
        return end.timeIntervalSince(startedAt) / 60
    }
}
