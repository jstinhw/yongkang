import Foundation

/// What the agents just finished, in the form a reviewer needs it: which tasks closed,
/// the sentence explaining how the work was split, what each agent reported and how it
/// checked it.
///
/// Nothing here is written for this screen. It is the agents' own reports, read the way
/// a person reads them before a commit — so a summary can never claim work the notebook
/// does not show.
package struct ChangeSummary: Equatable, Sendable {
    package var tasks: [SummaryTask] = []
    /// One line per session: how it chose to split the batch. The only design decision the
    /// app can quote rather than infer.
    var strategies: [String] = []

    /// Changed files no task reported owning: hand edits, or an agent that recorded no
    /// paths. Never silently folded into a task — an unattributed file is a thing to know.
    package var unclaimed: [FileChange] = []
    /// The longest bar on the screen, so a file's bar means the same thing under every
    /// task rather than being rescaled per card.
    package var peak: Int = 1

    /// Spelled out because the empty summary — what a project holds before anything has
    /// been read — is built from another target.
    package init(
        tasks: [SummaryTask] = [], strategies: [String] = [],
        unclaimed: [FileChange] = [], peak: Int = 1
    ) {
        self.tasks = tasks
        self.strategies = strategies
        self.unclaimed = unclaimed
        self.peak = peak
    }

    package var finished: [SummaryTask] { tasks.filter(\.done) }
    package var isEmpty: Bool { tasks.isEmpty && strategies.isEmpty }

    /// The strategy, then every decision a worker checkpointed — the two places a choice
    /// that outlives the run is written down.
    package var decisions: [String] {
        strategies + tasks.flatMap(\.work).map(\.checkpoint).filter { !$0.isEmpty }
    }

    /// Every task a session in this project was handed, done ones first, each carrying the
    /// work records filed against it and the files those workers reported owning.
    package static func of(_ project: Project, changes: [FileChange] = []) -> ChangeSummary {
        var work: [String: [LeadWork]] = [:]
        var strategies: [String] = []
        for (_, coordination) in plans(of: project) {
            let strategy = coordination.strategy.trimmingCharacters(in: .whitespacesAndNewlines)
            if !strategy.isEmpty && !strategies.contains(strategy) { strategies.append(strategy) }
            for worker in coordination.workers { work[worker.taskID, default: []].append(worker) }
        }
        // Attempts in the order they ran, across sessions, so the last one is the verdict.
        work = work.mapValues { attempts in
            attempts.enumerated().sorted { a, b in
                let (left, right) = (a.element.startedAt ?? .distantFuture, b.element.startedAt ?? .distantFuture)
                return left == right ? a.offset < b.offset : left < right
            }.map(\.element)
        }
        let handed = Set(work.keys).union(project.sessions.flatMap(\.taskIDs))
        let byPath = Dictionary(changes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var claimed: Set<String> = []
        let tasks = project.cards
            .filter { $0.kind == .task && handed.contains($0.id) }
            .map { card -> SummaryTask in
                let workers = work[card.id] ?? []
                // A file reported by two workers on the same task is one file, listed once
                // and counted once, in the order the workers named it.
                var files: [FileChange] = []
                for path in workers.flatMap(\.paths) where !files.contains(where: { $0.path == path }) {
                    guard let file = byPath[path] else { continue }
                    files.append(file)
                    claimed.insert(path)
                }
                // The records this task's workers wrote go in with its code, so the commit
                // carries the reason for itself. A path git does not list is left out.
                let records =
                    ([card.url]
                    + plans(of: project).flatMap { session, plan in
                        plan.workers.filter { $0.taskID == card.id }.map {
                            project.notebookRoot.appendingPathComponent("runs")
                                .appendingPathComponent("\(session.uuidString.lowercased())-work-\($0.id).md")
                        }
                    }).compactMap { relative($0, in: project.directory) }.filter { byPath[$0] != nil }
                return SummaryTask(
                    id: card.id, title: card.title, status: card.status, url: card.url,
                    body: card.body, work: workers, files: files, records: records)
            }
        return ChangeSummary(
            tasks: tasks.filter(\.done) + tasks.filter { !$0.done },
            strategies: strategies,
            unclaimed: changes.filter { !claimed.contains($0.path) },
            peak: max(1, changes.map { $0.added + $0.removed }.max() ?? 1))
    }

    /// Finished tasks whose work is still uncommitted — what is waiting on the user.
    package var waiting: [SummaryTask] { tasks.filter { $0.done && !$0.files.isEmpty } }

    /// The part of that one session holds: what turns its row in the Agents list green.
    package func waiting(for session: CodeSession) -> [SummaryTask] {
        waiting.filter { session.taskIDs.contains($0.id) }
    }

    /// Another task that changed the same file, which approving this one would carry along.
    package func sharing(_ path: String, besides task: SummaryTask) -> SummaryTask? {
        tasks.first { $0.id != task.id && !$0.commitPaths.isEmpty && $0.files.contains { $0.path == path } }
    }

    /// The records on disk, with a live session's own copy in place of its disk one — the
    /// live copy knows whether a worker is still running.
    static func plans(of project: Project) -> [(UUID, LeadCoordination)] {
        var plans = project.records
        for session in project.sessions { if let live = session.coordination { plans[session.id] = live } }
        return plans.sorted { $0.key.uuidString < $1.key.uuidString }.map { ($0.key, $0.value) }
    }

    private static func relative(_ url: URL, in directory: URL) -> String? {
        let base = directory.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : nil
    }

    /// A commit subject to edit instead of type. Only finished tasks go in it: naming work
    /// still in flight is a claim the repo would keep forever.
    package var commitMessage: String {
        let done = finished
        guard let first = done.first else { return "" }
        guard done.count > 1 else { return first.title }
        return "Finish \(done.count) tasks: " + done.map(\.title).joined(separator: ", ")
    }
}

/// One task in the summary, with the reports of the agents that built it.
package struct SummaryTask: Identifiable, Equatable, Sendable {
    package let id: String
    package var title: String
    package var status: String
    /// The task file, whose body is the brief and the "Done when" the review opens on.
    package var url: URL? = nil
    /// That body, carried from the card so the review never opens the file to draw it.
    package var body: String = ""
    package var work: [LeadWork] = []
    /// The changed files this task's workers reported owning, in the order they named them.
    package var files: [FileChange] = []
    /// Changed notebook files that belong to this task: its own file and its work records.
    var records: [String] = []

    /// What approving this task commits: its code and its records, nothing else.
    package var commitPaths: [String] {
        files.map(\.path) + records.filter { path in !files.contains { $0.path == path } }
    }

    package var done: Bool { status == "done" }
    package var added: Int { files.reduce(0) { $0 + $1.added } }
    package var removed: Int { files.reduce(0) { $0 + $1.removed } }
    /// How the latest attempt says it checked the work: what the reviewer reads before
    /// running anything themselves. Empty when nobody but the reviewer has checked it.
    package var verification: String { work.last?.verification ?? "" }
}
