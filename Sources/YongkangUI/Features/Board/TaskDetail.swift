import SwiftUI
import YongkangCore

/// One task's own page — what it is, what "done" means for it, and who is on it right now
/// — instead of the raw Markdown file. The checklist is the only progress a task actually
/// records, so it gets the room.
package struct TaskDetail: View {
    let card: NotebookCard
    let cards: [NotebookCard]
    /// Whether a still-open session already has this task.
    let assigned: Set<String>
    /// The subagents dispatched for this task, with the session that spawned each.
    let working: [(CodeSession, SubagentStatus)]
    let open: (URL) -> Void
    let agents: AgentChoice
    let assign: ([NotebookCard], AgentKind) -> Void
    let check: (CodeSession, SubagentStatus) -> Void

    @State private var content: [NotebookContent.Section] = []

    package init(
        card: NotebookCard,
        cards: [NotebookCard],
        assigned: Set<String>,
        working: [(CodeSession, SubagentStatus)],
        open: @escaping (URL) -> Void,
        agents: AgentChoice,
        assign: @escaping ([NotebookCard], AgentKind) -> Void,
        check: @escaping (CodeSession, SubagentStatus) -> Void
    ) {
        self.card = card
        self.cards = cards
        self.assigned = assigned
        self.working = working
        self.open = open
        self.agents = agents
        self.assign = assign
        self.check = check
    }

    private var locked: Bool { assigned.contains(card.id) || card.status == "done" }
    private var project: NotebookCard? {
        card.project.flatMap { id in cards.first { $0.id == id && $0.kind == .project } }
    }
    private var batch: [NotebookCard] {
        NotebookIndex.withBlockers([card], in: cards, excluding: assigned)
    }
    private var checklist: [NotebookContent.ChecklistItem] {
        content.flatMap { section in
            section.blocks.flatMap { block -> [NotebookContent.ChecklistItem] in
                if case .checklist(let items) = block { return items }
                return []
            }
        }
    }

    package var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if !content.isEmpty {
                            NotebookContentView(sections: content, cards: cards)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardSurface(padding: 16)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                inspector
            }
            actionBar
        }
        .background(Theme.bg)
        .task(id: card.body) { content = NotebookContent.sections(card.body) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                NotebookStyle.statusRing(
                    card.status,
                    progress: checklist.isEmpty
                        ? 0
                        : Double(checklist.filter(\.done).count) / Double(checklist.count),
                    size: 24
                )
                .padding(.top, 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title).font(Typography.title)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(card.id).font(Typography.mono).foregroundStyle(Theme.tx3)
                        if !card.status.isEmpty { NotebookStyle.pill(card.status) }
                        if assigned.contains(card.id) { NotebookStyle.pill("wip") }
                    }
                }
                Spacer(minLength: 12)
                Button {
                    open(card.url)
                } label: {
                    Label("Edit file", systemImage: "pencil")
                }
                .buttonStyle(.consoleGhost)
            }
            graph
        }
    }

    /// Where the task sits in the chain, as chips rather than a sentence: this is what the
    /// agent works from, so it should read at a glance.
    private var graph: some View {
        let blocks = NotebookStyle.dependents(of: card, in: cards)
        return HStack(spacing: 8) {
            ForEach(card.dependsOn, id: \.self) { id in
                NotebookStyle.chip("waits on \(id)", mono: true)
            }
            if !card.dependsOn.isEmpty {
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.tx4)
            }
            HStack(spacing: 6) {
                StateDot(color: NotebookStyle.color(of: card.status))
                Text("this task").font(Typography.caption).foregroundStyle(Theme.prose)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.raised))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            if !blocks.isEmpty {
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.tx4)
                ForEach(blocks, id: \.self) { id in
                    NotebookStyle.chip("blocks \(id)", mono: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        Inspector {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Working on it", trailing: working.isEmpty ? nil : "\(working.count)")
                if working.isEmpty {
                    Text(
                        locked
                            ? "No agent is on it right now."
                            : "Nobody yet — assign it to an agent."
                    )
                    .font(Typography.body).foregroundStyle(Theme.tx3)
                }
                ForEach(working, id: \.1.id) { session, subagent in
                    Button {
                        check(session, subagent)
                    } label: {
                        HStack(spacing: 10) {
                            RoleTile(role: subagent.agentType)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subagent.displayName).font(Typography.body)
                                    .foregroundStyle(Theme.tx)
                                Text(session.title).font(Typography.caption)
                                    .foregroundStyle(Theme.tx3).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            NotebookStyle.pill(
                                subagent.running ? "Running" : "Done",
                                subagent.running ? Theme.accent : Theme.green)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(radius: 10, padding: 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let project {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("In project")
                    HStack(spacing: 10) {
                        NotebookStyle.statusRing(project.status, progress: projectProgress, size: 16)
                        Text(project.title).font(Typography.body).foregroundStyle(Theme.tx2).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }

            if !checklist.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(
                        "Done when",
                        trailing: "\(checklist.filter(\.done).count) of \(checklist.count)")
                    MeterBar(
                        value: Double(checklist.filter(\.done).count) / Double(checklist.count),
                        tint: Theme.green)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var projectProgress: Double {
        guard let project else { return 0 }
        let tasks = cards.filter { $0.kind == .task && $0.project == project.id }
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.filter { $0.status == "done" }.count) / Double(tasks.count)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        ActionBar {
            Text(NotebookFormat.relativePath(card.url))
                .font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
            Spacer(minLength: 12)
            if locked {
                Text(
                    card.status == "done"
                        ? "Done — nothing to assign."
                        : "A session already has this task."
                )
                .font(Typography.body).foregroundStyle(Theme.tx3)
            } else if batch.count > 1 {
                Text("pulls in \(batch.count - 1) blocker\(batch.count == 2 ? "" : "s")")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
            }
            AssignButton(title: "Assign", choice: agents, disabled: locked) { assign([card], $0) }
        }
    }

}
