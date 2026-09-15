import SwiftUI

/// One finished task, read the way a person decides whether to accept it: what it was
/// for, what the reviewer said, and what each agent did. The code is one click further —
/// collapsed under Changes, each file opening its diff — because the verdict and the
/// reports are what most reviews need, and the diff is there for the ones that do not.
package struct TaskReview: View {
    let task: SummaryTask
    let summary: ChangeSummary
    let directory: URL
    let cards: [NotebookCard]
    let team: [TeamMember]
    let branch: String?
    let head: String?
    @Binding var draft: ReviewDraft
    let openFile: (String) -> Void
    let approve: (String) -> String?
    let requestChanges: () -> Void

    @State private var content: [NotebookContent.Section] = []
    /// Worked out from each file's diff once the page opens, so a data layer with SQL in
    /// it is flagged as Database before the reviewer expands anything.
    @State private var areas: [String: ReviewArea] = [:]

    package init(
        task: SummaryTask,
        summary: ChangeSummary,
        directory: URL,
        cards: [NotebookCard],
        team: [TeamMember],
        branch: String?,
        head: String?,
        draft: Binding<ReviewDraft>,
        openFile: @escaping (String) -> Void,
        approve: @escaping (String) -> String?,
        requestChanges: @escaping () -> Void
    ) {
        self.task = task
        self.summary = summary
        self.directory = directory
        self.cards = cards
        self.team = team
        self.branch = branch
        self.head = head
        self._draft = draft
        self.openFile = openFile
        self.approve = approve
        self.requestChanges = requestChanges
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
                        taskCard
                        reviewerCard
                        agentsCard
                        changesCard
                        FeedbackCard(draft: $draft, openFile: openFile)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.bg)
                inspector
            }
            TaskReviewBar(task: task, draft: draft, approve: approve, requestChanges: requestChanges)
        }
        .task(id: task.files) { load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NotebookStyle.statusRing(task.status, progress: 0, size: 20)
                Text(task.title).font(Typo.display(22)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 9) {
                if task.done {
                    NotebookStyle.pill(task.commitPaths.isEmpty ? "Committed" : "Ready for your review", Theme.green)
                } else {
                    NotebookStyle.pill(
                        "With the agents · \(task.status.isEmpty ? "queued" : task.status)", Theme.accent)
                }
                NotebookStyle.chip(task.id, mono: true)
                Text("\(task.files.count) file\(task.files.count == 1 ? "" : "s")")
                    .font(Typo.mono(12)).foregroundStyle(Theme.tx3)
                Text("+\(task.added)").font(Typo.mono(12)).foregroundStyle(Theme.green)
                Text("−\(task.removed)").font(Typo.mono(12)).foregroundStyle(Theme.red)
            }
            if !grouped.isEmpty {
                HStack(spacing: 8) {
                    ForEach(grouped, id: \.area) { group in areaTag(group.area, count: group.files.count) }
                }
            }
        }
    }

    private func areaTag(_ area: ReviewArea, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: area.systemImage).font(.system(size: 11))
            Text(area.rawValue).font(Typo.text(11.5, .medium))
            Text("\(count)").font(Typo.mono(10.5)).opacity(0.75)
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
                Text("The task file could not be read.").font(Typo.text(12)).foregroundStyle(Theme.tx3)
            } else {
                NotebookContentView(sections: content, cards: cards)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    // MARK: - Reviewer

    /// The latest QA pass in full — its verdict is the one that counts — and any earlier
    /// attempts as one line each, so a task that failed first reads as having failed first.
    private var reviewerCard: some View {
        let reviews = Array(task.reviews.reversed())
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Reviewer", trailing: reviews.count > 1 ? "\(reviews.count) passes" : nil)
            if let latest = reviews.first {
                WorkReport(work: latest, name: name(of: latest), cards: cards, openFile: nil)
                ForEach(Array(reviews.dropFirst().enumerated()), id: \.offset) { _, earlier in
                    HStack(spacing: 8) {
                        StateDot(color: NotebookStyle.color(of: earlier.state))
                        Text(earlier.id).font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                        Text(earlier.report).font(Typo.text(11.5)).foregroundStyle(Theme.tx2).lineLimit(1)
                    }
                }
            } else {
                Text(
                    task.done
                        ? "No QA record was filed against this task — nobody but you has checked it."
                        : "QA has not run yet."
                )
                .font(Typo.text(12)).foregroundStyle(task.done ? Theme.amber : Theme.tx3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    // MARK: - Agents

    private var agentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What the agents did", trailing: task.builds.isEmpty ? nil : "\(task.builds.count)")
            if task.builds.isEmpty {
                Text("No work records were filed against this task.")
                    .font(Typo.text(12)).foregroundStyle(Theme.tx3)
            }
            ForEach(Array(task.builds.enumerated()), id: \.offset) { _, work in
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

    /// The task's files by area, with how many lines each changed. The code itself is a
    /// click away on the file's own page, where a line can be commented on.
    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(
                "Changes by area",
                trailing: "\(task.files.count) file\(task.files.count == 1 ? "" : "s") · "
                    + "+\(task.added) −\(task.removed)")
            if task.files.isEmpty {
                Text("No uncommitted file is recorded against this task.")
                    .font(Typo.text(12)).foregroundStyle(Theme.tx3)
            }
            ForEach(grouped, id: \.area) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: group.area.systemImage).font(.system(size: 12)).foregroundStyle(
                            group.area.color)
                        Text(group.area.rawValue).font(Typo.text(12.5, .medium)).foregroundStyle(Theme.tx)
                        Spacer(minLength: 8)
                        Text(
                            "+\(group.files.reduce(0) { $0 + $1.added }) −\(group.files.reduce(0) { $0 + $1.removed })"
                        )
                        .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                    }
                    ForEach(group.files) { fileRow($0) }
                }
            }
            if !task.files.isEmpty {
                Text("Open a file to read its diff and comment on a line.")
                    .font(Typo.text(11)).foregroundStyle(Theme.tx3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private func fileRow(_ file: FileChange) -> some View {
        let comments = draft.comments.filter { $0.path == file.path }.count
        let owner = task.work.first { $0.paths.contains(file.path) }?.skill ?? ""
        return Button {
            openFile(file.path)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: file.untracked ? "doc.badge.plus" : "doc.text")
                    .font(.system(size: 11)).foregroundStyle(file.untracked ? Theme.green : Theme.tx3)
                Text(file.path).font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                    .lineLimit(1).truncationMode(.head)
                if !owner.isEmpty { RoleTile(role: owner, size: 16) }
                if summary.sharing(file.path, besides: task) != nil { NotebookStyle.pill("shared", Theme.amber) }
                Spacer(minLength: 8)
                if comments > 0 { NotebookStyle.pill("\(comments) comment\(comments == 1 ? "" : "s")", Theme.violet) }
                Text("+\(file.added)").font(Typo.mono(10.5)).foregroundStyle(Theme.green)
                Text("−\(file.removed)").font(Typo.mono(10.5)).foregroundStyle(Theme.red)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.tx4)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the diff")
    }

    // MARK: - Inspector

    private var inspector: some View {
        Inspector(width: 336) {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Verdict")
                verdictLine
                if !checklist.isEmpty {
                    fact("Done when", "\(checklist.filter(\.done).count) / \(checklist.count)")
                }
                fact("Your comments", "\(draft.comments.count)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 15)

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
                    Text(branch ?? "no branch").font(Typo.mono(11.5)).foregroundStyle(Theme.tx)
                    Spacer(minLength: 8)
                    Text("\(task.commitPaths.count) file\(task.commitPaths.count == 1 ? "" : "s")")
                        .font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                }
                Text("Only this task's files and its run records. Nothing is pushed.")
                    .font(Typo.text(11.5)).foregroundStyle(Theme.tx3).fixedSize(horizontal: false, vertical: true)
                if let head {
                    Text("on top of \(head)").font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(2)
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
        let latest = task.reviews.last
        HStack(spacing: 9) {
            if let latest {
                NotebookStyle.statusRing(latest.state, progress: 0, size: 16)
                Text(
                    latest.state == "done"
                        ? "QA passed" : latest.state == "failed" ? "QA sent it back" : "QA \(latest.state)"
                )
                .font(Typo.text(13.5, .medium)).foregroundStyle(Theme.tx)
            } else {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.amber)
                Text("No QA record").font(Typo.text(13.5, .medium)).foregroundStyle(Theme.amber)
            }
            Spacer(minLength: 0)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
            Spacer(minLength: 8)
            Text(value).font(Typo.mono(11.5)).foregroundStyle(Theme.tx)
        }
    }

    private func areaBar(_ area: ReviewArea, _ files: [FileChange]) -> some View {
        let lines = files.reduce(0) { $0 + $1.added + $1.removed }
        return HStack(spacing: 8) {
            Image(systemName: area.systemImage).font(.system(size: 11)).foregroundStyle(area.color).frame(width: 14)
            Text(area.rawValue).font(Typo.text(11.5)).foregroundStyle(Theme.tx2).frame(width: 104, alignment: .leading)
            Text("\(files.count)").font(Typo.mono(10)).foregroundStyle(Theme.tx3).frame(width: 16)
            MeterBar(value: Double(lines) / Double(max(1, task.added + task.removed)), tint: area.color, height: 5)
            Text("+\(files.reduce(0) { $0 + $1.added })").font(Typo.mono(10)).foregroundStyle(Theme.green)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func sharedWarning(_ file: FileChange, _ other: SummaryTask) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Theme.amber)
            Text("\(file.path) is also changed by \(other.title). Its edits in that file go into this commit too.")
                .font(Typo.text(11.5)).foregroundStyle(Theme.tx2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 12, border: Theme.amber.opacity(0.26), fill: Theme.amber.opacity(0.06))
    }

    private func load() {
        let text = task.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        content = NotebookContent.sections(NotebookIndex.body(text))
        var found: [String: ReviewArea] = [:]
        for file in task.files {
            let owner = task.work.first { $0.paths.contains(file.path) }?.skill ?? ""
            found[file.path] = ReviewArea.of(file.path, skill: owner, diff: GitChanges.diff(of: file, in: directory))
        }
        areas = found
    }
}
