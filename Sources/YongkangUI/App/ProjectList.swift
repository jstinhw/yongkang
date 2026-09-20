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
    /// What the working tree means, derived by the model rather than here: this column redraws on
    /// every poll, and `ChangeSummary.of` walks every card and every run record.
    let summary: ChangeSummary
    /// The toolbar's agent, which a project's context menu assigns to first, and what the
    /// shell found, so the other agents are offered but a missing one cannot be picked.
    let agent: AgentKind
    let found: Set<AgentKind>?
    let assign: ([NotebookCard], AgentKind) -> Void
    let closeSession: (CodeSession) -> Void
    /// Sends a notebook entry to the Trash — the only way work leaves the board.
    let remove: (NotebookCard) -> Void
    /// Every open project, for the switcher in the header, and the two ways out of this one.
    let projects: [Project]
    let open: (Project) -> Void
    let leave: () -> Void

    /// Agent trees start open; this only remembers the roots the user collapsed.
    @State private var collapsed: Set<UUID> = []

    package init(
        section: ConsoleSection,
        project: Project,
        selection: Binding<Route?>,
        showDone: Bool,
        summary: ChangeSummary,
        agent: AgentKind,
        found: Set<AgentKind>?,
        assign: @escaping ([NotebookCard], AgentKind) -> Void,
        closeSession: @escaping (CodeSession) -> Void,
        remove: @escaping (NotebookCard) -> Void,
        projects: [Project],
        open: @escaping (Project) -> Void,
        leave: @escaping () -> Void
    ) {
        self.section = section
        self.project = project
        self._selection = selection
        self.showDone = showDone
        self.summary = summary
        self.agent = agent
        self.found = found
        self.assign = assign
        self.closeSession = closeSession
        self.remove = remove
        self.projects = projects
        self.open = open
        self.leave = leave
    }

    package var body: some View {
        ListPane {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .board: boardRows
                    case .agents: agentRows
                    }
                }
                .padding(.bottom, 14)
            }
            footer
        }
    }

    // MARK: - Header and footer

    /// The project's name is the switcher: it is where you already look to see which project
    /// you are in. It goes with the list when ⌘\ hides it, and the toolbar shows the same menu
    /// until the list comes back.
    private var header: some View {
        Menu {
            ProjectSwitcherItems(projects: projects, current: project.id, open: open, leave: leave)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(Typography.headline).foregroundStyle(Theme.tx)
                    Text(project.directory.path)
                        .font(Typography.mono).foregroundStyle(Theme.tx3)
                        .lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tx3)
            }
            .contentShape(Rectangle())
        }
        // `.button` + `.plain` keeps this label as drawn; `.borderlessButton` flattens it to
        // one line of text.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Switch project")
        .accessibilityLabel("Project \(project.name). Switch project")
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var footer: some View {
        Text(footNote)
            .font(Typography.mono)
            .foregroundStyle(Theme.tx3)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var footNote: String {
        switch section {
        case .board:
            return "Tasks live on the board, in their project's build order. The arrow on a card opens its page."
        case .agents:
            return
                "A session opens its terminal. Each task under it opens its review; a green one is waiting for you. Clearing a block releases the agent waiting on it."
        }
    }

    // MARK: - Rows

    private func group(_ title: String, _ trailing: String? = nil) -> some View {
        SectionLabel(title, trailing: trailing)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    /// `selected` is for a row that stands for more than one route — a session, on either of
    /// its panes. Every other row is selected when the selection is its own route.
    private func row<Content: View>(
        _ route: Route, selected: Bool? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
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
        .rowSelection(selected ?? (selection == route))
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
                    let finished = tasks.allSatisfy { $0.status == "done" || project.assignedTaskIDs.contains($0.id) }
                    Button("Assign all tasks to \(agent.displayName)") { assign(tasks, agent) }
                        .disabled(finished || found?.contains(agent) == false)
                    OtherAgentMenu(title: "Assign all tasks to", agent: agent, found: found) { assign(tasks, $0) }
                        .disabled(finished)
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

    /// A project is busy while any of its tasks is out with a session.
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
        usageRow
        // Blocks sit above the sessions rather than in a section of their own: a block is the
        // one thing here that is the user's move, and it holds whichever session raised it.
        let blocked = project.blocks.filter(\.waiting)
        if !blocked.isEmpty {
            group("Waiting on you", "\(blocked.count)")
            ForEach(blocked) { blockRow($0) }
        }
        group("Agents", "\(project.onlineAgentCount) online")
        if project.sessions.isEmpty { empty("Nothing running") }
        // Each session, then the tasks it holds, then the subagents each task dispatched: a
        // session row opens its terminal, a task row that task's review.
        ForEach(project.sessions) { session in
            sessionRow(session)
                .contextMenu { Button("Close Session") { closeSession(session) } }
            if !collapsed.contains(session.id) {
                let tasks = tasks(of: session)
                ForEach(tasks) { task in
                    taskRow(task)
                    ForEach(subagents(of: session, on: [task.id])) { subagentRow($0, in: session, depth: 2) }
                }
                ForEach(subagents(of: session, besides: Set(tasks.map(\.id)))) {
                    subagentRow($0, in: session, depth: 1)
                }
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
        let running = session.activeSubagents.count
        let review = summary.waiting(for: session).count
        return row(.session(session.id), selected: selection?.pane(of: session.id) != nil) {
            HStack(spacing: 9) {
                if session.agent == nil {
                    Image(systemName: session.icon).font(.system(size: 12))
                        .foregroundStyle(session.exited ? Theme.tx4 : Theme.tx2)
                        .frame(width: 24, height: 24)
                } else {
                    RoleTile(role: session.holdsTasks ? "work" : session.title, size: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title).font(Typography.body(.medium))
                        .foregroundStyle(session.exited ? Theme.tx3 : Theme.tx)
                        .lineLimit(1)
                    Text(subtitle(of: session)).font(Typography.caption)
                        .foregroundStyle(review > 0 ? Theme.green : Theme.tx3)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if session.holdsTasks || !session.subagents.isEmpty {
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
                            ? "Show \(session.title)’s tasks and agents" : "Hide \(session.title)’s tasks and agents")
                }
                StateDot(
                    color: session.exited ? Theme.tx4 : (running > 0 ? Theme.accent : Theme.green),
                    live: running > 0 || review > 0)
            }
        }
    }

    private func subtitle(of session: CodeSession) -> String {
        guard let agent = session.agent else { return session.exited ? "exited" : "service" }
        guard session.holdsTasks else {
            return session.exited ? "exited" : agent.displayName
        }
        let running = session.activeSubagents.count
        let review = summary.waiting(for: session).count
        guard review == 0 else { return "\(review) ready for review" + (running > 0 ? " · \(running) running" : "") }
        return "\(session.taskIDs.count) task\(session.taskIDs.count == 1 ? "" : "s") · \(running) running"
    }

    private func toggle(_ session: CodeSession) {
        if collapsed.contains(session.id) { collapsed.remove(session.id) } else { collapsed.insert(session.id) }
    }

    /// The tasks a session holds, in the order it was handed them — its chain's build order.
    private func tasks(of session: CodeSession) -> [SummaryTask] {
        session.taskIDs.compactMap { id in summary.tasks.first { $0.id == id } }
    }

    /// A session's subagents named for one of `tasks`, running ones first.
    private func subagents(of session: CodeSession, on tasks: Set<String>) -> [SubagentStatus] {
        session.subagents.filter { tasks.contains($0.taskID ?? "") }.sorted { $0.running && !$1.running }
    }

    /// The rest, which sit under the session itself: named for no task it has a row for.
    private func subagents(of session: CodeSession, besides tasks: Set<String>) -> [SubagentStatus] {
        session.subagents.filter { !tasks.contains($0.taskID ?? "") }.sorted { $0.running && !$1.running }
    }

    /// A row `depth` levels under its session, with a guide line for each level.
    private func nested<Content: View>(_ depth: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle().fill(Theme.line).frame(width: 1).padding(.leading, 25)
            }
            content()
        }
    }

    /// One task under the session holding it. It opens the task's review — the brief, what
    /// the agent did and how it checked it — which is the same page Review opens.
    private func taskRow(_ task: SummaryTask) -> some View {
        let route = Route.reviewTask(task.id)
        let waiting = task.done && !task.files.isEmpty
        let (state, tint) = Self.state(of: task)
        return nested(1) {
            row(route) {
                HStack(spacing: 9) {
                    NotebookStyle.statusRing(task.status, progress: 0, size: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title).font(Typography.body)
                            .foregroundStyle(selection == route ? Theme.tx : Theme.tx2)
                            .lineLimit(1)
                        Text(state).font(Typography.caption).foregroundStyle(tint).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if waiting { StateDot(color: Theme.green, live: true).help("Waiting for your review") }
                }
            }
        }
    }

    /// What a task row says under its title: waiting on the user, finished, or still with the
    /// agent.
    private static func state(of task: SummaryTask) -> (String, Color) {
        if task.done {
            return task.files.isEmpty ? ("done", Theme.tx3) : ("ready for review · +\(task.added)", Theme.green)
        }
        if task.status == "blocked" { return ("blocked", Theme.amber) }
        return (task.status.isEmpty ? "queued" : task.status, Theme.tx3)
    }

    private func subagentRow(_ subagent: SubagentStatus, in session: CodeSession, depth: Int) -> some View {
        let route = Route.subagent(session: session.id, id: subagent.id)
        return nested(depth) {
            row(route) {
                HStack(spacing: 8) {
                    RoleTile(role: subagent.agentType, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(subagent.displayName).font(Typography.body(.medium))
                            .foregroundStyle(selection == route ? Theme.tx : Theme.tx2)
                            .lineLimit(1)
                        // The label underneath is still the link to the task: a session names
                        // every subagent after its task id, and that is what matches it back.
                        Text(subagent.description).font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    StateDot(color: subagent.running ? Theme.accent : Theme.green, live: subagent.running)
                }
            }
        }
    }

    /// One block, named for the task it holds. A demo is the same file for a design nobody
    /// has approved yet; a proposal, for work nobody has said yes to.
    private func blockRow(_ block: UserBlock) -> some View {
        row(.block(block.id)) {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: block.isProposal
                        ? "lightbulb" : (block.isDemo ? "rectangle.on.rectangle" : "hand.raised")
                )
                .font(.system(size: 13))
                .foregroundStyle(block.isProposal ? Theme.violet : Theme.amber)
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

/// What the project menu holds, wherever it is drawn: the list header, or the toolbar while the
/// list is hidden. ⌘[ is not repeated on All Projects — Go → All Projects owns that binding.
struct ProjectSwitcherItems: View {
    let projects: [Project]
    let current: Project.ID
    let open: (Project) -> Void
    let leave: () -> Void

    var body: some View {
        Section("Open Projects") {
            ForEach(projects) { other in
                // A Toggle is what draws the check. Choosing the project you are already in does
                // nothing: entering it again would drop you back on the board.
                Toggle(
                    title(other),
                    isOn: Binding(
                        get: { other.id == current },
                        set: { _ in if other.id != current { open(other) } }))
            }
        }
        Divider()
        Button("All Projects", action: leave)
    }

    /// A menu item cannot carry the amber dot the Fleet cards do, so what is waiting on you is
    /// said in words.
    private func title(_ other: Project) -> String {
        let waiting = other.blocks.filter(\.waiting).count
        return waiting == 0 ? other.name : "\(other.name) — \(waiting) waiting on you"
    }
}
