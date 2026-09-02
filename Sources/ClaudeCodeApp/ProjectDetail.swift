import SwiftUI

/// One project's own page — what it's for, how far along it is, and its tasks grouped by
/// state. The board next door is the cross-project build order; this is the one project,
/// the way Linear opens a project rather than a graph.
struct ProjectDetail: View {
    let card: NotebookCard
    let cards: [NotebookCard]
    /// The project folder, which is what `repos:` paths are relative to.
    let directory: URL
    /// Tasks a still-open Engineering Lead session already has — shown as WIP and not
    /// pickable for a new batch.
    let assigned: Set<String>
    let showDone: Bool
    let open: (URL) -> Void
    let assign: ([NotebookCard]) -> Void
    let run: (NotebookCard) -> Void
    /// Opens a task's own page — separate from picking it, which the ring does.
    let openTask: (NotebookCard) -> Void

    @State private var picked: Set<String> = []
    @State private var content: [NotebookContent.Section] = []

    private var allTasks: [NotebookCard] {
        NotebookIndex.ordered(cards.filter { $0.kind == .task && $0.project == card.id })
    }
    private var tasks: [NotebookCard] { NotebookIndex.visible(allTasks, showDone: showDone) }
    private var done: Int { allTasks.filter { $0.status == "done" }.count }

    private var pickedTasks: [NotebookCard] {
        NotebookIndex.ordered(tasks.filter { picked.contains($0.id) })
    }
    private var batch: [NotebookCard] {
        NotebookIndex.withBlockers(pickedTasks, in: cards, excluding: assigned)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if !content.isEmpty {
                        NotebookContentView(sections: content, cards: cards,
                                            redundant: Set(allTasks.map(\.id)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface(padding: 16)
                    }
                    repos
                    taskList
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            assignBar
        }
        .background(Theme.bg)
        .task(id: card.id) { load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                NotebookStyle.statusRing(card.status,
                                         progress: allTasks.isEmpty ? 0 : Double(done) / Double(allTasks.count),
                                         size: 26)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title).font(Typo.display(22))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(card.id).font(Typo.mono(11)).foregroundStyle(Theme.tx3)
                        if !card.status.isEmpty { NotebookStyle.pill(card.status) }
                        if let roadmap = card.roadmap.flatMap({ id in
                            cards.first { $0.id == id && $0.kind == .roadmap }
                        }) {
                            NotebookStyle.chip("for \(roadmap.title)")
                        }
                    }
                }
                Spacer(minLength: 12)
                Button { open(card.url) } label: { Label("Edit file", systemImage: "pencil") }
                    .buttonStyle(.consoleGhost)
                Button { run(card) } label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.console)
                    .help("Run this project's services")
            }
            if !allTasks.isEmpty {
                HStack(spacing: 10) {
                    MeterBar(value: Double(done) / Double(allTasks.count),
                             tint: NotebookStyle.color(of: card.status))
                        .frame(width: 180)
                    Text("\(done) of \(allTasks.count) done")
                        .font(Typo.mono(11.5)).foregroundStyle(Theme.tx2)
                }
            }
            if let waits = NotebookStyle.edge("waits on ", card.dependsOn, in: cards) {
                waits.font(Typo.mono(10.5))
            }
        }
    }

    // MARK: - Repos

    /// What the work touches, and whether it can be started. A repo that is not on disk
    /// yet — the usual state before anything is scaffolded — says so in amber rather than
    /// looking like a repo with nothing to run.
    @ViewBuilder private var repos: some View {
        let plan = Service.plan(for: card, in: directory)
        if !plan.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Repos")
                ForEach(plan, id: \.repo) { step in
                    let missing = !FileManager.default.fileExists(atPath: step.directory.path)
                    HStack(spacing: 7) {
                        Image(systemName: missing ? "questionmark.folder" : "folder")
                            .font(.system(size: 11)).foregroundStyle(Theme.tx3)
                        Text(step.repo).font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                        Text(missing ? "not created yet" : summary(step.services))
                            .font(Typo.text(11))
                            .foregroundStyle(missing || step.services.allSatisfy { $0.command == nil }
                                             ? Theme.amber : Theme.tx3)
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

    /// Active work first, then what's next, then what's stuck, then what's shipped.
    private var taskList: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Tasks", trailing: "\(tasks.count)")
            if tasks.isEmpty {
                Text(allTasks.isEmpty ? "This project has no tasks yet."
                                      : "All tasks are complete. Use Completed to view them.")
                    .font(Typo.text(12)).foregroundStyle(Theme.tx3)
            } else {
                ForEach(["active", "blocked", "todo", "done"], id: \.self) { group($0) }
            }
        }
    }

    @ViewBuilder private func group(_ status: String) -> some View {
        let rows = tasks.filter { $0.status == status || (status == "todo" && $0.status.isEmpty) }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    StateDot(color: NotebookStyle.color(of: status))
                    Text(status.uppercased()).font(Typo.section).tracking(1.4)
                        .foregroundStyle(Theme.tx3)
                    Text("\(rows.count)").font(Typo.mono(10)).foregroundStyle(Theme.tx4)
                }
                VStack(spacing: 1) {
                    ForEach(rows) { row($0) }
                }
                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Theme.line2, lineWidth: 1))
            }
        }
    }

    /// The ring toggles the pick for batch assignment; the rest of the row opens the
    /// task's own page — two buttons sharing one row instead of one overloaded click.
    private func row(_ task: NotebookCard) -> some View {
        let locked = assigned.contains(task.id) || task.status == "done"
        return HStack(spacing: 10) {
            Button {
                if picked.contains(task.id) { picked.remove(task.id) } else { picked.insert(task.id) }
            } label: {
                // ponytail: a fixed fill for "active" — a task's real progress is its
                // checklist, which the task page reads; this row only carries state.
                NotebookStyle.statusRing(task.status, progress: task.status == "active" ? 0.4 : 0)
            }
            .buttonStyle(.plain)
            .disabled(locked)

            Button { openTask(task) } label: {
                HStack(spacing: 8) {
                    Text(task.title).font(Typo.text(12.5)).foregroundStyle(Theme.tx).lineLimit(1)
                    if assigned.contains(task.id) { NotebookStyle.pill("wip") }
                    Spacer(minLength: 8)
                    if let waits = NotebookStyle.edge("waits on ", task.dependsOn, in: cards) {
                        waits.font(Typo.mono(10))
                    }
                    Text(task.id).font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(picked.contains(task.id) ? Theme.accent.opacity(0.10) : Color.clear)
        .opacity(locked ? 0.6 : 1)
    }

    // MARK: - Assign bar

    private var assignBar: some View {
        ActionBar {
            if pickedTasks.isEmpty {
                Text("Click a task's ring to pick it for an engineering lead.")
                    .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
            } else {
                let pulled = batch.count - pickedTasks.count
                Text("\(pickedTasks.count) picked").font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                if pulled > 0 {
                    Text("· \(pulled) blocker\(pulled == 1 ? "" : "s") pulled in")
                        .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
                }
                Text(batch.map(\.id).joined(separator: " → "))
                    .font(Typo.mono(11)).foregroundStyle(Theme.tx3).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Clear") { picked.removeAll() }
                .buttonStyle(.consoleGhost)
                .disabled(picked.isEmpty)
            Button { assign(batch) } label: {
                Label("Assign to Engineering Lead",
                      systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(.consolePrimary)
            .disabled(batch.isEmpty)
        }
    }

    private func load() {
        let text = (try? String(contentsOf: card.url, encoding: .utf8)) ?? ""
        content = NotebookContent.sections(NotebookIndex.body(text))
    }
}
