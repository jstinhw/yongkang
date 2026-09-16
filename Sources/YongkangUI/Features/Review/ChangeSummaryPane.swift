import SwiftUI
import YongkangCore

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
            Text(headlineText).font(Typography.title)
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
                    .font(Typography.mono).foregroundStyle(Theme.tx3)
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
            if file.counted {
                Text("+\(file.added)").font(Typography.mono).foregroundStyle(Theme.green)
                    .frame(width: 44, alignment: .trailing)
                Text("−\(file.removed)").font(Typography.mono).foregroundStyle(Theme.red)
                    .frame(width: 44, alignment: .trailing)
            } else {
                // The width of the two counts and the gap between them, so the bars stay aligned.
                Text("new file").font(Typography.mono).foregroundStyle(Theme.green)
                    .frame(width: 98, alignment: .trailing)
            }
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
                        .font(Typography.mono).foregroundStyle(Theme.tx2)
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
                    .font(Typography.body).foregroundStyle(Theme.tx)
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
                    Text(line).font(Typography.body).foregroundStyle(Theme.tx2)
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
        .font(Typography.body).foregroundStyle(Theme.tx3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }
}
