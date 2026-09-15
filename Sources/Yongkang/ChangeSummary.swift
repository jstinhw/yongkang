import SwiftUI

/// What the agents just finished, in the form a reviewer needs it: which tasks closed,
/// the sentence explaining how the work was split, what each specialist reported and what
/// QA said about it.
///
/// Nothing here is written for this screen. It is the lead's own run records, read the way
/// a person reads them before a commit — so a summary can never claim work the notebook
/// does not show.
struct ChangeSummary: Equatable {
    var tasks: [SummaryTask] = []
    /// One line per lead: how it chose to split the batch. The only design decision the
    /// app can quote rather than infer.
    var strategies: [String] = []

    /// Changed files no task reported owning: hand edits, or a lead that recorded no
    /// paths. Never silently folded into a task — an unattributed file is a thing to know.
    var unclaimed: [FileChange] = []
    /// The longest bar on the screen, so a file's bar means the same thing under every
    /// task rather than being rescaled per card.
    var peak: Int = 1

    var finished: [SummaryTask] { tasks.filter(\.done) }
    var isEmpty: Bool { tasks.isEmpty && strategies.isEmpty }

    /// The strategy, then every decision a worker checkpointed — the two places a choice
    /// that outlives the run is written down.
    var decisions: [String] {
        strategies + tasks.flatMap(\.work).map(\.checkpoint).filter { !$0.isEmpty }
    }

    /// Every task a lead in this project was handed, done ones first, each carrying the
    /// work records filed against it and the files those workers reported owning.
    static func of(_ project: Project, changes: [FileChange] = []) -> ChangeSummary {
        var work: [String: [LeadWork]] = [:]
        var strategies: [String] = []
        for (_, coordination) in plans(of: project) {
            let strategy = coordination.strategy.trimmingCharacters(in: .whitespacesAndNewlines)
            if !strategy.isEmpty && !strategies.contains(strategy) { strategies.append(strategy) }
            for worker in coordination.workers { work[worker.taskID, default: []].append(worker) }
        }
        // Attempts in the order they ran, across leads, so the last QA pass is the verdict.
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
                    work: workers, files: files, records: records)
            }
        return ChangeSummary(
            tasks: tasks.filter(\.done) + tasks.filter { !$0.done },
            strategies: strategies,
            unclaimed: changes.filter { !claimed.contains($0.path) },
            peak: max(1, changes.map { $0.added + $0.removed }.max() ?? 1))
    }

    /// Finished tasks whose work is still uncommitted — what is waiting on the user.
    var waiting: [SummaryTask] { tasks.filter { $0.done && !$0.files.isEmpty } }

    /// Another task that changed the same file, which approving this one would carry along.
    func sharing(_ path: String, besides task: SummaryTask) -> SummaryTask? {
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
    var commitMessage: String {
        let done = finished
        guard let first = done.first else { return "" }
        guard done.count > 1 else { return first.title }
        return "Finish \(done.count) tasks: " + done.map(\.title).joined(separator: ", ")
    }
}

/// One task in the summary, with the specialists that built it and the ones that reviewed it.
struct SummaryTask: Identifiable, Equatable {
    let id: String
    var title: String
    var status: String
    /// The task file, whose body is the brief and the "Done when" the review opens on.
    var url: URL? = nil
    var work: [LeadWork] = []
    /// The changed files this task's workers reported owning, in the order they named them.
    var files: [FileChange] = []
    /// Changed notebook files that belong to this task: its own file and its work records.
    var records: [String] = []

    /// What approving this task commits: its code and its records, nothing else.
    var commitPaths: [String] { files.map(\.path) + records.filter { path in !files.contains { $0.path == path } } }

    var done: Bool { status == "done" }
    var added: Int { files.reduce(0) { $0 + $1.added } }
    var removed: Int { files.reduce(0) { $0 + $1.removed } }
    /// QA is the one specialist whose report is a verdict on someone else's work, so it
    /// reads apart from the builds it accepted.
    var reviews: [LeadWork] { work.filter { $0.skill.lowercased().contains("qa") } }
    var builds: [LeadWork] { work.filter { !$0.skill.lowercased().contains("qa") } }
}

/// The Review screen before you pick a file: the batch in words and in shape, so the diff
/// underneath is read with the reason for it already on screen.
struct ChangeSummaryPane: View {
    let summary: ChangeSummary
    let changes: [FileChange]
    let select: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headline
                ForEach(summary.tasks) { card($0) }
                if !summary.unclaimed.isEmpty { unclaimed }
                if !summary.decisions.isEmpty { decisions }
                if summary.isEmpty { unrecorded }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Headline

    private var headline: some View {
        let added = changes.reduce(0) { $0 + $1.added }
        let removed = changes.reduce(0) { $0 + $1.removed }
        let done = summary.finished.count
        let flight = summary.tasks.count - done
        return VStack(alignment: .leading, spacing: 9) {
            Text(headlineText).font(Typo.display(22))
            HStack(spacing: 9) {
                Text("\(changes.count) file\(changes.count == 1 ? "" : "s")")
                    .font(Typo.mono(12)).foregroundStyle(Theme.tx3)
                Text("+\(added)").font(Typo.mono(12)).foregroundStyle(Theme.green)
                Text("−\(removed)").font(Typo.mono(12)).foregroundStyle(Theme.red)
                if done > 0 {
                    NotebookStyle.pill("\(done) passed QA", Theme.green)
                }
                if flight > 0 {
                    NotebookStyle.pill("\(flight) still in flight", Theme.accent)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The batch is what this screen is about, so it is what the headline counts. The file
    /// total moves to the line under it — that is the commit's size, not the work's shape.
    private var headlineText: String {
        guard !summary.tasks.isEmpty else {
            return changes.isEmpty ? "Nothing to commit" : "Changes with no batch behind them"
        }
        let count = summary.tasks.count
        return "\(count) task\(count == 1 ? "" : "s") to review"
    }

    // MARK: - Change shape

    /// A task's own diff as a shape: one bar per file it reported owning, biggest first, so
    /// the size and balance of that task's work read before any of it is opened. Bars are
    /// on one scale across the whole screen, so a big task looks bigger. A bar opens that
    /// file's diff.
    private func shape(_ files: [FileChange], label: String, trailing: String? = nil) -> some View {
        let ranked = files.sorted { $0.added + $0.removed > $1.added + $1.removed }
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label, trailing: trailing)
            ForEach(ranked.prefix(8)) { file in
                Button {
                    select(file.path)
                } label: {
                    bar(file, peak: summary.peak)
                }
                .buttonStyle(.plain)
            }
            if ranked.count > 8 {
                Text("+\(ranked.count - 8) more file\(ranked.count == 9 ? "" : "s") in the list")
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bar(_ file: FileChange, peak: Int) -> some View {
        HStack(spacing: 10) {
            Text(file.name).font(Typo.mono(10.5)).foregroundStyle(Theme.tx2)
                .frame(width: 170, alignment: .leading).lineLimit(1).truncationMode(.middle)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(Theme.green)
                        .frame(width: geo.size.width * Double(file.added) / Double(peak))
                    Capsule().fill(Theme.red)
                        .frame(width: geo.size.width * Double(file.removed) / Double(peak))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            Text("+\(file.added)").font(Typo.mono(10)).foregroundStyle(Theme.green)
                .frame(width: 44, alignment: .trailing)
            Text("−\(file.removed)").font(Typo.mono(10)).foregroundStyle(Theme.red)
                .frame(width: 44, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Tasks

    private func card(_ task: SummaryTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NotebookStyle.statusRing(task.status, progress: 0, size: 18)
                Text(task.title).font(Typo.text(14, .medium)).foregroundStyle(Theme.tx)
                    .fixedSize(horizontal: false, vertical: true)
                NotebookStyle.chip(task.id, mono: true)
                Spacer(minLength: 8)
                if !task.status.isEmpty { NotebookStyle.pill(task.status) }
            }
            if !task.work.isEmpty { pipeline(task) }
            if task.files.isEmpty {
                Text(
                    task.work.contains { !$0.paths.isEmpty }
                        ? "The files this task reported are not in the working tree — already "
                            + "committed, or renamed since."
                        : "No files are recorded against this task, so its diff cannot be told "
                            + "apart from the rest."
                )
                .font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                shape(
                    task.files, label: "What it changed",
                    trailing: "+\(task.added) −\(task.removed)")
            }
            // Positional ids: two leads that ran the same task in turn can file the same
            // work id twice, and a summary must not drop the second one.
            ForEach(Array(task.builds.enumerated()), id: \.offset) { _, work in report(work) }
            if !task.reviews.isEmpty {
                SectionLabel("Reviewed by QA")
                ForEach(Array(task.reviews.enumerated()), id: \.offset) { _, work in report(work) }
            } else if task.done {
                Text("No QA record was filed against this task.")
                    .font(Typo.text(11.5)).foregroundStyle(Theme.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    /// How the task actually ran: each specialist in build-then-review order with the state
    /// it ended in — the shape of the batch, not a sentence about it.
    private func pipeline(_ task: SummaryTask) -> some View {
        let ordered = task.builds + task.reviews
        return HStack(spacing: 7) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { index, work in
                if index > 0 {
                    Image(systemName: "arrow.right").font(.system(size: 10))
                        .foregroundStyle(Theme.tx4)
                }
                HStack(spacing: 6) {
                    RoleTile(role: work.skill, size: 18)
                    Text(work.skill.isEmpty ? work.id : work.skill)
                        .font(Typo.mono(10)).foregroundStyle(Theme.tx2)
                    StateDot(
                        color: NotebookStyle.color(of: work.state),
                        live: work.runtimeRunning == true)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
            }
            Spacer(minLength: 0)
        }
    }

    /// One specialist in its own words: what it was for, and what it reported back.
    private func report(_ work: LeadWork) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(work.title.isEmpty ? work.id : work.title)
                    .font(Typo.text(12)).foregroundStyle(Theme.tx)
                Spacer(minLength: 8)
                if !work.model.isEmpty { NotebookStyle.chip(work.model, mono: true) }
                NotebookStyle.pill(work.state)
            }
            if !work.report.isEmpty {
                Text(work.report).font(Typo.text(11.5)).foregroundStyle(Theme.tx2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !work.reason.isEmpty {
                Text(work.reason).font(Typo.text(11)).foregroundStyle(Theme.tx3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 10, padding: 11, fill: Theme.raised)
    }

    /// Everything in the tree that no task claimed. It is still going into the commit, so
    /// it is shown rather than quietly left out of the arithmetic.
    private var unclaimed: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle").font(.system(size: 15))
                    .foregroundStyle(Theme.amber)
                Text("Not claimed by a task").font(Typo.text(14, .medium)).foregroundStyle(Theme.tx)
                Spacer(minLength: 8)
                NotebookStyle.pill(
                    "\(summary.unclaimed.count) file"
                        + (summary.unclaimed.count == 1 ? "" : "s"), Theme.amber)
            }
            shape(summary.unclaimed, label: "In the commit anyway")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    // MARK: - Decisions

    private var decisions: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Design decisions")
            ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 9) {
                    StateDot(color: Theme.violet).padding(.top, 5)
                    Text(line).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private var unrecorded: some View {
        Text(
            "No agent batch is recorded against this working tree — these changes were "
                + "made outside the console. The diff and the commit bar still work."
        )
        .font(Typo.text(12)).foregroundStyle(Theme.tx3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }
}
