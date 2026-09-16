import AppKit
import SwiftUI
import YongkangCore

/// The column beside the rail: whatever its current section is a list of. One column per
/// section rather than one tree holding everything at once — the old sidebar made you read
/// past the notebook to find the agent you were watching.
package struct ProjectList: View {
    let section: ConsoleSection
    let project: Project
    @Binding var selection: Route?
    let showDone: Bool
    /// Only read when the Review section is showing; empty everywhere else.
    let changes: [FileChange]
    /// What those changes mean, derived by the model rather than here: this column redraws on
    /// every poll, and `ChangeSummary.of` walks every card and every run record.
    let summary: ChangeSummary
    let assign: ([NotebookCard]) -> Void
    let closeSession: (CodeSession) -> Void
    /// Sends a notebook entry to the Trash — the only way work leaves the board.
    let remove: (NotebookCard) -> Void

    /// Agent trees start open; this only remembers the roots the user collapsed.
    @State private var collapsed: Set<UUID> = []

    package init(
        section: ConsoleSection,
        project: Project,
        selection: Binding<Route?>,
        showDone: Bool,
        changes: [FileChange],
        summary: ChangeSummary,
        assign: @escaping ([NotebookCard]) -> Void,
        closeSession: @escaping (CodeSession) -> Void,
        remove: @escaping (NotebookCard) -> Void
    ) {
        self.section = section
        self.project = project
        self._selection = selection
        self.showDone = showDone
        self.changes = changes
        self.summary = summary
        self.assign = assign
        self.closeSession = closeSession
        self.remove = remove
    }

    package var body: some View {
        ListPane {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .overview: overviewRows
                    case .board: boardRows
                    case .agents: agentRows
                    case .review: reviewRows
                    case .blocks: blockRows
                    }
                }
                .padding(.bottom, 14)
            }
            // The sidebar would otherwise paint the system's own scroll ground over the panel.
            .scrollContentBackground(.hidden)
            footer
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack(spacing: 9) {
            Text("yk")
                .font(Typography.mono(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).font(Typography.headline).foregroundStyle(Theme.tx)
                Text(project.directory.path)
                    .font(Typography.mono).foregroundStyle(Theme.tx3)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder private var footer: some View {
        if let note = footNote {
            Text(note)
                .font(Typography.mono)
                .foregroundStyle(Theme.tx3)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    private var footNote: String? {
        switch section {
        case .board:
            return "Tasks live on the board, in their project's build order. The arrow on a card opens its page."
        case .agents:
            return
                "Select any agent or subagent to view its live session transcript. Completed agents stay available here."
        case .blocks:
            return
                "A block is one file in .notebook/blocks/. Clearing it releases the agent waiting on it. A demo is the same thing for a design nobody has approved yet."
        case .review: return "Nothing is committed until you approve it here. No agent commits, pushes or opens a PR."
        default: return nil
        }
    }

    // MARK: - Rows

    private func group(_ title: String, _ trailing: String? = nil) -> some View {
        SectionLabel(title, trailing: trailing)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func row<Content: View>(_ route: Route, @ViewBuilder content: () -> Content) -> some View {
        Button {
            selection = route
        } label: {
            content()
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Every row in the column goes through here, so one line makes each of them
                // read as a row — title, id, state, counts — rather than as four stops. A
                // session row's own disclosure button joins as an action on that row.
                .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .rowSelection(selection == route)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private func cardRow(_ card: NotebookCard, route: Route) -> some View {
        row(route) {
            HStack(alignment: .top, spacing: 10) {
                NotebookStyle.statusRing(card.status, progress: progress(of: card), size: 14)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(Typography.body)
                        .foregroundStyle(selection == route ? Theme.tx : Theme.tx2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(card.id).font(Typography.monoCaption).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let done = taskCount(of: card) {
                    Text(done).font(Typography.mono).foregroundStyle(Theme.tx3)
                }
                if project.assignedTaskIDs.contains(card.id) && card.status != "done" {
                    NotebookStyle.pill("wip")
                }
            }
            .opacity(card.status == "done" ? 0.6 : 1)
        }
    }

    /// How far a project's tasks have got, in words rather than only as a ring — the board
    /// no longer repeats those tasks in this column, so the row has to say it.
    private func taskCount(of card: NotebookCard) -> String? {
        guard card.kind == .project else { return nil }
        let tasks = project.cards.filter { $0.kind == .task && $0.project == card.id }
        guard !tasks.isEmpty else { return nil }
        return "\(tasks.filter { $0.status == "done" }.count)/\(tasks.count)"
    }

    private func progress(of card: NotebookCard) -> Double {
        guard card.kind == .project else { return card.status == "active" ? 0.55 : 0 }
        let tasks = project.cards.filter { $0.kind == .task && $0.project == card.id }
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.filter { $0.status == "done" }.count) / Double(tasks.count)
    }

    // MARK: - Overview

    @ViewBuilder private var overviewRows: some View {
        let online = project.sessions.filter { $0.agent != nil && !$0.exited }
        group("Agents online", "\(online.reduce(0) { $0 + $1.activeSubagents.count } + online.count)")
        if online.isEmpty {
            empty("No agents running")
        } else {
            ForEach(online) { session in
                sessionRow(session)
                ForEach(session.activeSubagents) { subagent in
                    subagentRow(subagent, in: session)
                }
            }
        }
        group("Notebook")
        ForEach(NotebookKindCount.all(in: project.cards), id: \.label) { item in
            HStack(spacing: 9) {
                Image(systemName: item.icon).font(.system(size: 12)).foregroundStyle(Theme.tx3)
                Text(item.label).font(Typography.body).foregroundStyle(Theme.tx2)
                Spacer(minLength: 8)
                Text("\(item.count)").font(Typography.mono).foregroundStyle(Theme.tx3)
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Board

    @ViewBuilder private var boardRows: some View {
        row(.board) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.split.3x1").font(.system(size: 12))
                    .foregroundStyle(selection == .board ? Theme.accent : Theme.tx3)
                Text("Board").font(Typography.body)
                    .foregroundStyle(selection == .board ? Theme.tx : Theme.tx2)
            }
        }
        let roadmaps = NotebookIndex.ordered(project.cards.filter { $0.kind == .roadmap })
        if !roadmaps.isEmpty {
            group("Roadmap", "\(roadmaps.count)")
            ForEach(roadmaps) { cardRow($0, route: .page($0.id)) }
        }
        let projects = visible(project.cards.filter { $0.kind == .project })
        group("Projects", "\(projects.count)")
        if projects.isEmpty { empty("No projects yet") }
        ForEach(projects) { card in
            let tasks = project.cards.filter { $0.kind == .task && $0.project == card.id }
            cardRow(card, route: .project(card.id))
                .contextMenu {
                    Button("Assign all tasks to Engineering Lead") { assign(tasks) }
                        .disabled(
                            tasks.allSatisfy {
                                $0.status == "done" || project.assignedTaskIDs.contains($0.id)
                            })
                    menu(for: card)
                }
        }
        // No task rows here any more: the board draws every project's tasks as its chain,
        // and this column listing the same ones again was half of why the screen read as
        // busy. A card's own arrow opens its page.
        if let scope = scopedProject {
            let memory = project.cards.filter { $0.kind == .memory && $0.project == scope.id }
            if !memory.isEmpty {
                group("Memory", "\(memory.count)")
                ForEach(memory) { card in
                    row(.page(card.id)) {
                        HStack(spacing: 9) {
                            Image(systemName: "brain").font(.system(size: 11)).foregroundStyle(Theme.tx3)
                            Text(card.title).font(Typography.body).foregroundStyle(Theme.tx2).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func menu(for card: NotebookCard) -> CardMenu {
        CardMenu(card: card, busy: isBusy(card), remove: remove)
    }

    /// A project is busy while any of its tasks is out with a lead.
    private func isBusy(_ card: NotebookCard) -> Bool {
        guard card.kind == .project else { return project.assignedTaskIDs.contains(card.id) }
        return project.cards.contains {
            $0.kind == .task && $0.project == card.id
                && project.assignedTaskIDs.contains($0.id)
        }
    }

    /// The project the board is scoped to: whatever is selected, or the project a selected
    /// task belongs to, so its tasks stay listed while you read one.
    private var scopedProject: NotebookCard? {
        if case .project(let id) = selection {
            return project.cards.first { $0.id == id && $0.kind == .project }
        }
        if case .task(let id) = selection,
            let task = project.cards.first(where: { $0.id == id }), let owner = task.project
        {
            return project.cards.first { $0.id == owner && $0.kind == .project }
        }
        return visible(project.cards.filter { $0.kind == .project }).first
    }

    private func visible(_ cards: [NotebookCard]) -> [NotebookCard] {
        NotebookIndex.ordered(
            showDone
                ? cards
                : cards.filter {
                    $0.kind == .project
                        ? !NotebookIndex.isFinished($0, in: project.cards)
                        : $0.status != "done"
                })
    }

    // MARK: - Agents

    @ViewBuilder private var agentRows: some View {
        group("Fleet")
        usageRow
        group("Sessions", "\(project.onlineAgentCount) online")
        if project.sessions.isEmpty { empty("Nothing running") }
        ForEach(project.sessions) { session in
            sessionRow(session)
                .contextMenu { Button("Close Session") { closeSession(session) } }
            if !collapsed.contains(session.id) {
                ForEach(session.subagents.sorted { $0.running && !$1.running }) { subagentRow($0, in: session) }
            }
        }
        if !project.team.isEmpty {
            group("Team", "\(project.team.count)")
            ForEach(project.team) { teamRow($0) }
        }
    }

    /// A standing member of the Engineering Lead's team — a name and the skill it runs.
    /// Not a session: opening one reads the agent itself, not a transcript.
    private func teamRow(_ member: TeamMember) -> some View {
        let route = Route.member(member.name)
        return row(route) {
            HStack(spacing: 9) {
                RoleTile(role: member.skills.first ?? member.name, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.name).font(Typography.body(.medium))
                        .foregroundStyle(selection == route ? Theme.tx : Theme.tx2).lineLimit(1)
                    Text(member.skills.joined(separator: ", "))
                        .font(Typography.caption).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Spacer(minLength: 6)
            }
        }
    }

    /// The one row here that is not an agent: what the whole fleet has spent, and how
    /// close each coding tool is to the limit that would stop it.
    private var usageRow: some View {
        row(.usage) {
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 12)).foregroundStyle(Theme.tx2)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Usage").font(Typography.body(.medium)).foregroundStyle(Theme.tx)
                    Text("Limits, models, roles").font(Typography.caption).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 6)
            }
        }
    }

    private func sessionRow(_ session: CodeSession) -> some View {
        // Agent and service rows open their live sessions.
        let running = session.activeSubagents.count
        return row(.session(session.id)) {
            HStack(spacing: 9) {
                if session.agent == nil {
                    Image(systemName: session.icon).font(.system(size: 12))
                        .foregroundStyle(session.exited ? Theme.tx4 : Theme.tx2)
                        .frame(width: 24, height: 24)
                } else {
                    RoleTile(role: session.isEngineeringLead ? "lead" : session.title, size: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title).font(Typography.body(.medium))
                        .foregroundStyle(session.exited ? Theme.tx3 : Theme.tx)
                        .lineLimit(1)
                    Text(subtitle(of: session)).font(Typography.caption).foregroundStyle(Theme.tx3)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if !session.subagents.isEmpty {
                    Button {
                        toggle(session)
                    } label: {
                        Image(systemName: collapsed.contains(session.id) ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.tx3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(
                        collapsed.contains(session.id)
                            ? "Show \(session.title)’s agents" : "Hide \(session.title)’s agents")
                }
                StateDot(
                    color: session.exited ? Theme.tx4 : (running > 0 ? Theme.accent : Theme.green),
                    live: running > 0)
            }
        }
    }

    private func subtitle(of session: CodeSession) -> String {
        guard let agent = session.agent else { return session.exited ? "exited" : "service" }
        guard session.isEngineeringLead else {
            return session.exited ? "exited" : agent.displayName
        }
        let running = session.activeSubagents.count
        return "\(session.taskIDs.count) task\(session.taskIDs.count == 1 ? "" : "s") · \(running) running"
    }

    private func toggle(_ session: CodeSession) {
        if collapsed.contains(session.id) { collapsed.remove(session.id) } else { collapsed.insert(session.id) }
    }

    private func subagentRow(_ subagent: SubagentStatus, in session: CodeSession) -> some View {
        let route = Route.subagent(session: session.id, id: subagent.id)
        return HStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(width: 1).padding(.leading, 25)
            row(route) {
                HStack(spacing: 8) {
                    RoleTile(role: subagent.agentType, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(subagent.displayName).font(Typography.body(.medium))
                            .foregroundStyle(selection == route ? Theme.tx : Theme.tx2)
                            .lineLimit(1)
                        // The label underneath is still the link to the task: the lead names
                        // every subagent `<task-id>-<skill>`, and that is what matches it back.
                        Text(subagent.description).font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    StateDot(color: subagent.running ? Theme.accent : Theme.green, live: subagent.running)
                }
            }
        }
    }

    // MARK: - Review

    /// Tasks, not files: what is waiting for the user's approval first, then what the agents
    /// are still on. The whole working tree is one row at the end, for edits no task claims.
    @ViewBuilder private var reviewRows: some View {
        let waiting = summary.waiting
        let flight = summary.tasks.filter { !$0.done }
        group("Waiting for you", "\(waiting.count)")
        if waiting.isEmpty { empty("Nothing waiting for review") }
        ForEach(waiting) { task in
            reviewRow(
                task,
                detail: "\(task.files.count) file\(task.files.count == 1 ? "" : "s") · "
                    + (task.reviews.isEmpty ? "no QA record" : "QA passed"))
        }
        if !flight.isEmpty {
            group("With the agents", "\(flight.count)")
            ForEach(flight) { task in reviewRow(task, detail: task.status.isEmpty ? "queued" : task.status) }
        }
        let added = changes.reduce(0) { $0 + $1.added }
        let removed = changes.reduce(0) { $0 + $1.removed }
        group("Working tree", "+\(added) −\(removed)")
        row(.review(file: nil)) {
            HStack(spacing: 9) {
                Image(systemName: summary.unclaimed.isEmpty ? "doc.on.doc" : "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(summary.unclaimed.isEmpty ? Theme.tx3 : Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All changes").font(Typography.body).foregroundStyle(Theme.tx)
                    Text(
                        summary.unclaimed.isEmpty
                            ? "\(changes.count) files"
                            : "\(summary.unclaimed.count) not claimed by a task"
                    )
                    .font(Typography.caption).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func reviewRow(_ task: SummaryTask, detail: String) -> some View {
        row(.reviewTask(task.id)) {
            HStack(alignment: .top, spacing: 10) {
                NotebookStyle.statusRing(task.status, progress: 0, size: 14).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(Typography.body)
                        .foregroundStyle(selection == .reviewTask(task.id) ? Theme.tx : Theme.tx2)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(detail).font(Typography.caption).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Spacer(minLength: 4)
                if !task.files.isEmpty {
                    Text("+\(task.added)").font(Typography.mono).foregroundStyle(Theme.green)
                }
                if task.done && !task.files.isEmpty {
                    StateDot(color: Theme.green, live: true).padding(.top, 5).help("Waiting for your review")
                }
            }
        }
    }

    // MARK: - Blocks

    @ViewBuilder private var blockRows: some View {
        let waiting = project.blocks.filter(\.waiting)
        let resolved = project.blocks.filter { !$0.waiting }
        group("Waiting on you", "\(waiting.count)")
        if waiting.isEmpty { empty("Nothing waiting on you") }
        ForEach(waiting) { blockRow($0) }
        if !resolved.isEmpty && showDone {
            group("Resolved", "\(resolved.count)")
            ForEach(resolved) { blockRow($0).opacity(0.55) }
        }
    }

    private func blockRow(_ block: UserBlock) -> some View {
        row(.block(block.id)) {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: block.waiting
                        ? (block.isProposal
                            ? "lightbulb"
                            : block.isDemo ? "rectangle.on.rectangle" : "hand.raised")
                        : "checkmark.circle"
                )
                .font(.system(size: 13))
                .foregroundStyle(
                    block.waiting
                        ? (block.isProposal ? Theme.violet : Theme.amber)
                        : Theme.green
                )
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title).font(Typography.body)
                        .foregroundStyle(selection == .block(block.id) ? Theme.tx : Theme.tx2)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if block.isProposal {
                        Text(block.proposalReady ? "ready to create" : "product needs feedback")
                            .font(Typography.caption).foregroundStyle(Theme.tx3)
                    } else if let task = block.task {
                        Text(block.isDemo ? "demo · \(task)" : "holds \(task)")
                            .font(Typography.caption).foregroundStyle(Theme.tx3).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(Theme.tx4)
            .padding(.horizontal, 19)
            .padding(.vertical, 8)
    }
}

/// The notebook's shape in one line per kind — what the overview column counts.
struct NotebookKindCount {
    let label: String
    let icon: String
    let count: Int

    static func all(in cards: [NotebookCard]) -> [NotebookKindCount] {
        [
            NotebookKindCount(
                label: "Roadmap", icon: "map",
                count: cards.filter { $0.kind == .roadmap }.count),
            NotebookKindCount(
                label: "Projects", icon: "shippingbox",
                count: cards.filter { $0.kind == .project }.count),
            NotebookKindCount(
                label: "Tasks", icon: "checkmark.circle",
                count: cards.filter { $0.kind == .task }.count),
            NotebookKindCount(
                label: "Memory", icon: "brain",
                count: cards.filter { $0.kind == .memory }.count),
        ]
    }
}
