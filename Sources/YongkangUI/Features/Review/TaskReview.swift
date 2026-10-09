import SwiftUI
import YongkangCore

/// One finished task, read the way a person decides whether to accept it — in ten seconds when
/// the agent wrote a `## Review`: one sentence of what changed, how sure the agent is, what it
/// checked, what it reaches and what it left for you, then the questions and the few places it
/// says a person should read, then the evidence. The code is folded under Code changes, each
/// file unfolding its own diff, for the reviews that need more.
///
/// Without a review — a record from before them, or one the agent got wrong — the page falls
/// back to the task, the agents' reports and their Verification, which is all there is to show.
///
/// The same page on a task's row and on its session's Page, so the two cannot drift apart.
package struct TaskReview: View {
    let task: SummaryTask
    let summary: ChangeSummary
    let directory: URL
    let cards: [NotebookCard]
    let team: [TeamMember]
    let branch: String?
    let head: String?
    @Binding var draft: ReviewDraft
    /// What only the user can do for this task: open blocks and demos naming it.
    let blocks: [UserBlock]
    let openFile: (String) -> Void
    let openBlock: (UserBlock) -> Void
    /// Starts the session that walks the user through a block.
    let startBlock: (UserBlock) -> Void
    let approve: (String) async -> String?
    let requestChanges: () -> Void
    let discard: () -> Void
    /// What was sent for one of the review's questions, or nil before anything was.
    let answered: (String) -> String?
    let answer: (_ question: String, _ answer: String) -> Void

    @State private var content: [NotebookContent.Section] = []
    /// Worked out from each file's diff once the page opens, so a data layer with SQL in
    /// it is flagged as Database before the reviewer expands anything.
    @State private var areas: [String: ReviewArea] = [:]
    /// The same read's lines, kept for the files the reviewer unfolds.
    @State private var diffs: [String: [DiffLine]] = [:]
    @State private var unfolded: Set<String> = []

    package init(
        task: SummaryTask,
        summary: ChangeSummary,
        directory: URL,
        cards: [NotebookCard],
        team: [TeamMember],
        branch: String?,
        head: String?,
        draft: Binding<ReviewDraft>,
        blocks: [UserBlock],
        openFile: @escaping (String) -> Void,
        openBlock: @escaping (UserBlock) -> Void,
        startBlock: @escaping (UserBlock) -> Void,
        approve: @escaping (String) async -> String?,
        requestChanges: @escaping () -> Void,
        discard: @escaping () -> Void,
        answered: @escaping (String) -> String? = { _ in nil },
        answer: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.task = task
        self.summary = summary
        self.directory = directory
        self.cards = cards
        self.team = team
        self.branch = branch
        self.head = head
        self._draft = draft
        self.blocks = blocks
        self.openFile = openFile
        self.openBlock = openBlock
        self.startBlock = startBlock
        self.approve = approve
        self.requestChanges = requestChanges
        self.discard = discard
        self.answered = answered
        self.answer = answer
    }

    private var checklist: [NotebookContent.ChecklistItem] {
        content.flatMap { $0.blocks }.flatMap { block -> [NotebookContent.ChecklistItem] in
            if case .checklist(let items) = block { return items }
            return []
        }
    }

    private var grouped: [(area: ReviewArea, files: [FileChange])] {
        ReviewArea.allCases.compactMap { area in
            let files = task.files.filter { (areas[$0.path] ?? .other) == area }
            return files.isEmpty ? nil : (area, files)
        }
    }

    package var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let review = task.review {
                            ReviewGlance(
                                review: review, task: task, areas: grouped.map(\.area), blocks: blocks.count,
                                questions: (review.questions ?? []).filter { answered($0.ask) == nil }.count)
                        }
                        ForEach(blocks) { NeedsYouCard(block: $0, cards: cards, open: openBlock, start: startBlock) }
                        if let review = task.review {
                            reviewed(review)
                        } else {
                            if let problem = task.reviewProblem { unreadable(problem) }
                            taskCard
                            agentsCard
                            checkedCard
                        }
                        changesCard
                        FeedbackCard(
                            draft: $draft, history: task.work.filter { !$0.changeRequest.isEmpty },
                            cards: cards, openFile: openFile)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.bg)
                inspector
            }
            TaskReviewBar(
                task: task, draft: draft, cautioned: task.review?.cautions == true, approve: approve,
                requestChanges: requestChanges, discard: discard)
        }
        .task(id: task.body) { content = NotebookContent.sections(task.body) }
        .task(id: task.files) { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NotebookStyle.statusRing(task.status, progress: 0, size: 20)
                Text(task.title).font(Typography.title).fixedSize(horizontal: false, vertical: true)
            }
            if let summary = task.review?.summary {
                Text(summary).font(Typography.headline.weight(.regular)).foregroundStyle(Theme.prose)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 9) {
                if task.done && !task.commitPaths.isEmpty && task.review?.cautions == true {
                    NotebookStyle.pill("Done, with a caution", Theme.red)
                } else if task.done {
                    NotebookStyle.pill(task.commitPaths.isEmpty ? "Committed" : "Ready for your review", Theme.green)
                } else {
                    NotebookStyle.pill(
                        "With the agents · \(task.status.isEmpty ? "queued" : task.status)", Theme.accent)
                }
                NotebookStyle.chip(task.id, mono: true)
                Text("\(task.files.count) file\(task.files.count == 1 ? "" : "s")")
                    .font(Typography.code).foregroundStyle(Theme.tx3)
                Text("+\(task.added)").font(Typography.code).foregroundStyle(Theme.green)
                Text("−\(task.removed)").font(Typography.code).foregroundStyle(Theme.red)
            }
            // The glance says what the work reaches when there is a review.
            if !grouped.isEmpty && task.review == nil {
                HStack(spacing: 8) {
                    ForEach(grouped, id: \.area) { group in areaTag(group.area, count: group.files.count) }
                }
            }
        }
    }

    // MARK: - The review

    /// The agent's review, most urgent first: what it asks of you, what changed, the evidence,
    /// and what it is still worried about.
    @ViewBuilder private func reviewed(_ review: WorkReview) -> some View {
        if !(review.questions ?? []).isEmpty || !(review.spots ?? []).isEmpty {
            ReviewAsks(
                review: review, diffs: diffs, loading: diffs.isEmpty && !task.files.isEmpty, draft: $draft,
                answered: answered, answer: answer, openFile: openFile)
        }
        ReviewChanged(changed: review.changed ?? []) {
            ForEach(Array(task.work.enumerated()), id: \.offset) { _, work in
                WorkReport(work: work, name: name(of: work), cards: cards, openFile: openFile)
            }
        }
        ReviewSafety(checks: review.checks ?? [], holds: review.holds ?? [])
        if let concerns = review.concerns, !concerns.isEmpty { ReviewConcerns(concerns: concerns) }
    }

    /// The agent wrote a review the page could not read: said, with the field, so the reviewer
    /// can send it back, and the page carries on with the reports it can read.
    private func unreadable(_ problem: String) -> some View {
        Label {
            Text("The agent’s review could not be read: \(problem)").font(Typography.body).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 12, border: Theme.amber.opacity(0.26), fill: Theme.amber.opacity(0.06))
    }

    private func areaTag(_ area: ReviewArea, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: area.systemImage).font(.system(size: 11))
            Text(area.rawValue).font(Typography.body(.medium))
            Text("\(count)").font(Typography.mono).opacity(0.75)
        }
        .foregroundStyle(area.color)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(area.color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(area.color.opacity(0.24), lineWidth: 1))
    }

    // MARK: - The task

    @ViewBuilder private var taskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("The task", trailing: task.url.map(NotebookFormat.relativePath))
            if content.isEmpty {
                Text("The task file could not be read.").font(Typography.body).foregroundStyle(Theme.tx3)
            } else {
                NotebookContentView(sections: content, cards: cards)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    // MARK: - Checked

    /// How the latest attempt says it checked the work — the commands it ran and what they
    /// printed — so what is already verified is read before anything is run again.
    private var checkedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Self-review")
            if task.verification.isEmpty {
                Text(
                    task.done
                        ? "No verification was recorded against this task — nobody but you has checked it."
                        : "Not checked yet."
                )
                .font(Typography.body).foregroundStyle(task.done ? Theme.amber : Theme.tx3)
            } else {
                NotebookContentView(sections: NotebookContent.sections(task.verification), cards: cards)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    // MARK: - Agents

    private var agentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What changed", trailing: task.work.count > 1 ? "\(task.work.count) rounds" : nil)
            if task.work.isEmpty {
                Text("No work records were filed against this task.")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
            }
            ForEach(Array(task.work.enumerated()), id: \.offset) { _, work in
                WorkReport(work: work, name: name(of: work), cards: cards, openFile: openFile)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    /// The roster member whose skills include this work's — the name the user knows the
    /// agent by, rather than the skill folder it loaded.
    private func name(of work: LeadWork) -> String {
        team.first { $0.skills.contains(work.skill) }?.name ?? ""
    }

    // MARK: - Changes

    /// The task's files by area, with how many lines each changed. The code stays folded: a
    /// file unfolds its diff in place, where a line can be commented on.
    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(
                "Code changes",
                trailing: "\(task.files.count) file\(task.files.count == 1 ? "" : "s") · "
                    + "+\(task.added) −\(task.removed)")
            if task.files.isEmpty {
                Text("No uncommitted file is recorded against this task.")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
            }
            ForEach(grouped, id: \.area) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: group.area.systemImage).font(.system(size: 12)).foregroundStyle(
                            group.area.color)
                        Text(group.area.rawValue).font(Typography.body(.medium)).foregroundStyle(Theme.tx)
                        Spacer(minLength: 8)
                        Text(
                            "+\(group.files.reduce(0) { $0 + $1.added }) −\(group.files.reduce(0) { $0 + $1.removed })"
                        )
                        .font(Typography.mono).foregroundStyle(Theme.tx3)
                    }
                    ForEach(group.files) { fileRow($0) }
                }
            }
            if !task.files.isEmpty {
                Text("Unfold a file to read its diff, then click a line to comment on it.")
                    .font(Typography.caption).foregroundStyle(Theme.tx3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private func fileRow(_ file: FileChange) -> some View {
        let open = unfolded.contains(file.path)
        return VStack(alignment: .leading, spacing: 0) {
            fileHeader(file, open: open)
            if open {
                Group {
                    if let lines = diffs[file.path] {
                        ScrollView(.horizontal) {
                            DiffLines(path: file.path, lines: lines, draft: $draft).padding(.vertical, 6)
                        }
                    } else {
                        Text("Reading the diff…").font(Typography.body).foregroundStyle(Theme.tx3).padding(10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fileHeader(_ file: FileChange, open: Bool) -> some View {
        let comments = draft.comments.filter { $0.path == file.path }.count
        let owner = task.work.first { $0.paths.contains(file.path) }?.skill ?? ""
        return Button {
            if open { unfolded.remove(file.path) } else { unfolded.insert(file.path) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tx3).frame(width: 10)
                Image(systemName: file.untracked ? "doc.badge.plus" : "doc.text")
                    .font(.system(size: 11)).foregroundStyle(file.untracked ? Theme.green : Theme.tx3)
                Text(file.path).font(Typography.mono).foregroundStyle(Theme.tx2)
                    .lineLimit(1).truncationMode(.head)
                if let why = task.review?.files?.first(where: { $0.path == file.path })?.why {
                    Text(why).font(Typography.caption).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                if !owner.isEmpty { RoleTile(role: owner, size: 16) }
                if summary.sharing(file.path, besides: task) != nil { NotebookStyle.pill("shared", Theme.amber) }
                Spacer(minLength: 8)
                if comments > 0 { NotebookStyle.pill("\(comments) comment\(comments == 1 ? "" : "s")", Theme.violet) }
                if file.counted {
                    Text("+\(file.added)").font(Typography.mono).foregroundStyle(Theme.green)
                    Text("−\(file.removed)").font(Typography.mono).foregroundStyle(Theme.red)
                } else {
                    Text("new file").font(Typography.mono).foregroundStyle(Theme.green)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.raised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(open ? "Fold the diff" : "Unfold the diff")
        .accessibilityLabel("\(file.path), \(open ? "unfolded" : "folded")")
    }

    // MARK: - Inspector

    private var inspector: some View {
        Inspector(width: 336) {
            if let review = task.review {
                taskCard
                ReviewReach(outside: review.outside ?? [], next: review.next)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Verdict")
                    verdictLine
                    if !checklist.isEmpty {
                        fact("Done when", "\(checklist.filter(\.done).count) / \(checklist.count)")
                    }
                    if !blocks.isEmpty { fact("Needs you", "\(blocks.count)") }
                    fact("Your comments", "\(draft.comments.count)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(padding: 15)
            }

            if !grouped.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Areas", trailing: "+\(task.added) −\(task.removed)")
                    ForEach(grouped, id: \.area) { group in areaBar(group.area, group.files) }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("This commit")
                HStack(spacing: 9) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.accent)
                    // Wraps rather than truncates, for the same reason as in `ChangeReview`:
                    // the tail of a branch name is what identifies it.
                    Text(branch ?? "no branch").font(Typography.code).foregroundStyle(Theme.tx)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("\(task.commitPaths.count) file\(task.commitPaths.count == 1 ? "" : "s")")
                        .font(Typography.body).foregroundStyle(Theme.tx3)
                }
                Text("Only this task's files and its run records. Nothing is pushed.")
                    .font(Typography.body).foregroundStyle(Theme.tx3).fixedSize(horizontal: false, vertical: true)
                if let head {
                    Text("on top of \(head)").font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 15)

            ForEach(
                task.files.compactMap { file in summary.sharing(file.path, besides: task).map { (file, $0) } },
                id: \.0.path
            ) { file, other in
                sharedWarning(file, other)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var verdictLine: some View {
        HStack(spacing: 9) {
            if let latest = task.work.last, !task.verification.isEmpty {
                NotebookStyle.statusRing(latest.state, progress: 0, size: 16)
                Text(latest.state == "failed" ? "Failed its own check" : "Checked by the agent")
                    .font(Typography.headline).foregroundStyle(Theme.tx)
            } else {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.amber)
                Text(task.work.isEmpty ? "No report" : "Not verified")
                    .font(Typography.headline).foregroundStyle(Theme.amber)
            }
            Spacer(minLength: 0)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typography.body).foregroundStyle(Theme.tx3)
            Spacer(minLength: 8)
            Text(value).font(Typography.code).foregroundStyle(Theme.tx)
        }
    }

    private func areaBar(_ area: ReviewArea, _ files: [FileChange]) -> some View {
        let lines = files.reduce(0) { $0 + $1.added + $1.removed }
        return HStack(spacing: 8) {
            Image(systemName: area.systemImage).font(.system(size: 11)).foregroundStyle(area.color).frame(width: 14)
            Text(area.rawValue).font(Typography.body).foregroundStyle(Theme.tx2).frame(width: 104, alignment: .leading)
            Text("\(files.count)").font(Typography.mono).foregroundStyle(Theme.tx3).frame(width: 16)
            MeterBar(value: Double(lines) / Double(max(1, task.added + task.removed)), tint: area.color, height: 5)
            Text("+\(files.reduce(0) { $0 + $1.added })").font(Typography.mono).foregroundStyle(Theme.green)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func sharedWarning(_ file: FileChange, _ other: SummaryTask) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Theme.amber)
            Text("\(file.path) is also changed by \(other.title). Its edits in that file go into this commit too.")
                .font(Typography.body).foregroundStyle(Theme.tx2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 12, border: Theme.amber.opacity(0.26), fill: Theme.amber.opacity(0.06))
    }

    private func load() async {
        var found: [String: ReviewArea] = [:]
        var lines: [String: [DiffLine]] = [:]
        for file in task.files {
            let owner = task.work.first { $0.paths.contains(file.path) }?.skill ?? ""
            lines[file.path] = await GitClient.diff(of: file, in: directory)
            found[file.path] = ReviewArea.of(file.path, skill: owner, diff: lines[file.path] ?? [])
        }
        // The files changed while git was diffing, and a newer load has them.
        guard !Task.isCancelled else { return }
        areas = found
        diffs = lines
    }
}
