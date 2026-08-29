import SwiftUI

/// One project's own page — what it's for, how far along it is, and its tasks — the
/// way Linear opens a project: a description and a status-grouped issue list, not the
/// cross-project dependency board.
struct ProjectDetail: View {
    let card: NotebookCard
    let cards: [NotebookCard]
    /// The project folder, which is what `repos:` paths are relative to.
    let directory: URL
    /// Tasks a still-open Engineering Lead session already has — shown as WIP and not
    /// pickable for a new batch.
    let assigned: Set<String>
    let open: (URL) -> Void
    let assign: ([NotebookCard]) -> Void
    let run: (NotebookCard) -> Void
    /// Opens a task's own page — separate from picking it, which the rest of the row does.
    let openTask: (NotebookCard) -> Void

    @State private var picked: Set<String> = []
    @State private var content: [NotebookContent.Section] = []

    private var tasks: [NotebookCard] {
        NotebookIndex.ordered(cards.filter { $0.kind == .task && $0.project == card.id })
    }
    private var done: Int { tasks.filter { $0.status == "done" }.count }

    private var pickedTasks: [NotebookCard] {
        NotebookIndex.ordered(tasks.filter { picked.contains($0.id) })
    }
    private var batch: [NotebookCard] {
        NotebookIndex.withBlockers(pickedTasks, in: cards, excluding: assigned)
    }
    private var single: NotebookCard? {
        picked.count == 1 ? tasks.first { picked.contains($0.id) } : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !content.isEmpty { description }
                    repos
                    taskList
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            assignBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: card.id) { load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                NotebookStyle.statusRing(card.status, progress: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count), size: 20)
                Text(card.title)
                    .font(.title2.weight(.semibold))
                if !card.status.isEmpty { NotebookStyle.pill(card.status) }
                Spacer(minLength: 12)
                Button("Edit", systemImage: "pencil") { open(card.url) }
                    .buttonStyle(.borderless)
                Button("Run", systemImage: "play.fill") { run(card) }
                    .buttonStyle(.borderless)
                    .help("Run this project's services")
            }
            if !tasks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView(value: Double(done), total: Double(tasks.count))
                        .progressViewStyle(.linear)
                        .tint(NotebookStyle.color(of: card.status))
                        .frame(width: 160)
                    Text("\(done) of \(tasks.count) done")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let waits = NotebookStyle.edge("waits on ", card.dependsOn, in: cards) { waits.font(.caption) }
            if let blocks = NotebookStyle.edge("blocks ", NotebookStyle.dependents(of: card, in: cards), in: cards) {
                blocks.font(.caption)
            }
        }
    }

    // MARK: - Description

    /// The project's own file, parsed rather than shown raw — intro prose, then
    /// whatever's headed underneath it. A `## Tasks` list that is nothing but links to
    /// this project's own tasks is dropped: the task list below already shows them.
    private var description: some View {
        NotebookContentView(sections: content, cards: cards, redundant: Set(tasks.map(\.id)))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func load() {
        let text = (try? String(contentsOf: card.url, encoding: .utf8)) ?? ""
        content = NotebookContent.sections(NotebookIndex.body(text))
    }

    // MARK: - Repos

    /// What the work touches, and whether it can be started. A repo that is not on disk
    /// yet — the usual state before anything is scaffolded — says so in orange rather than
    /// looking like a repo with nothing to run.
    private var repos: some View {
        let plan = Service.plan(for: card, in: directory)
        return Group {
            if !plan.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan, id: \.repo) { step in
                        let missing = !FileManager.default.fileExists(atPath: step.directory.path)
                        HStack(spacing: 5) {
                            Image(systemName: missing ? "questionmark.folder" : "folder")
                            Text(step.repo)
                            Text(missing ? "not created yet" : summary(step.services))
                                .foregroundStyle(missing || step.services.allSatisfy { $0.command == nil }
                                                ? Color.orange : .secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func summary(_ services: [Service.Runnable]) -> String {
        guard services.count > 1 else { return services.first?.command ?? "nothing to run" }
        let runnable = services.filter { $0.command != nil }.count
        return "\(services.count) services" + (runnable < services.count ? " (\(runnable) runnable)" : "")
    }

    // MARK: - Tasks

    /// Active work first, then what's next, then what's stuck, then what's shipped —
    /// Linear groups a project's issues by status the same way.
    private var taskList: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Tasks", count: tasks.count)
            if tasks.isEmpty {
                Text("This project has no tasks yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(["active", "blocked", "todo", "done"], id: \.self) { status in
                    group(status)
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ status: String) -> some View {
        let rows = tasks.filter { $0.status == status || (status == "todo" && $0.status.isEmpty) }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(status.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 1) {
                    ForEach(rows) { task in row(task) }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    /// The ring toggles the pick for batch assignment; the rest of the row opens the
    /// task's own page — the two things Linear splits between a row's checkbox and its
    /// title, done here as two buttons sharing one row instead of one overloaded click.
    private func row(_ task: NotebookCard) -> some View {
        let locked = assigned.contains(task.id) || task.status == "done"
        return HStack(spacing: 8) {
            Button {
                if picked.contains(task.id) { picked.remove(task.id) } else { picked.insert(task.id) }
            } label: {
                // ponytail: a fixed fill for "active" — a task has no sub-progress of its
                // own, just a state. Swap for a real fraction if tasks grow checklists.
                NotebookStyle.statusRing(task.status, progress: task.status == "active" ? 0.4 : 0)
            }
            .buttonStyle(.plain)
            .disabled(locked)

            Button { openTask(task) } label: {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if assigned.contains(task.id) { NotebookStyle.pill("wip") }
                    Spacer(minLength: 8)
                    if let waits = NotebookStyle.edge("waits on ", task.dependsOn, in: cards) { waits.font(.caption2) }
                    Text(task.id)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(picked.contains(task.id) ? Color.accentColor.opacity(0.12) : Color.clear)
        .opacity(locked ? 0.6 : 1)
    }

    private func heading(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Assign bar

    private var assignBar: some View {
        HStack(spacing: 10) {
            if pickedTasks.isEmpty {
                Text("Click task rows to pick them for an engineering lead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let pulled = batch.count - pickedTasks.count
                Text("\(pickedTasks.count) picked" + (pulled > 0 ? " · \(pulled) blocker\(pulled == 1 ? "" : "s") pulled in" : ""))
                    .font(.callout)
                Text(batch.map(\.id).joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            Button("Open File") { single.map { open($0.url) } }
                .disabled(single == nil)
            Button("Clear") { picked.removeAll() }
                .disabled(picked.isEmpty)
            Button("Assign to Engineering Lead") { assign(batch) }
                .buttonStyle(.borderedProminent)
                .disabled(batch.isEmpty)
        }
        .padding(12)
    }
}
