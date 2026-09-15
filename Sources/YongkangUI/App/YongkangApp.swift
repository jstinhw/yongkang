import AppKit
import Combine
import SwiftUI
import YongkangCore

package struct YongkangApp: App {
    @State private var model = AppModel()

    // ponytail: poll instead of an FSEvents watcher. The agents in the console write
    // these files while you watch them; re-listing a few dozen paths every 2s is less
    // code than a recursive watcher and the tree is tiny. Revisit at thousands of files.
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    package init() {}

    package var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onReceive(tick) { _ in model.reload() }
        }
        .windowToolbarStyle(.unified)
    }
}

/// The window. It draws what `AppModel` and the entered `ProjectModel` hold and turns the
/// user's gestures into calls on them. What it keeps itself is layout, the sheets it has
/// open, and the settings `@AppStorage` persists.
struct RootView: View {
    @Bindable var model: AppModel
    /// Which folders were open last time. Sessions are not restored — the agents died
    /// with the app — but the projects and their notebooks come back.
    @AppStorage("openProjects") private var openProjects = "[]"
    /// The list column's width, dragged from its trailing divider, and whether it is
    /// collapsed. Both persist: a window you have sized once should come back that way.
    @AppStorage("listWidth") private var listWidth = 268.0
    @AppStorage("listHidden") private var listHidden = false
    /// The provider for every new agent session. Running sessions keep the provider they
    /// started with; switching a process underneath a live PTY is not possible.
    @AppStorage("agentKind") private var agent = AgentKind.claude
    /// The list width the current resize drag started from; nil when nothing is dragging.
    @State private var dragBase: Double?
    /// The "New → Agent…" sheet, adding one file to `.notebook/team/`.
    @State private var addingAgent = false
    /// The new-project sheet, opened from the Fleet page's own tile: a prompt, which is
    /// also what says where its folder goes.
    @State private var creatingProject = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()
            // ponytail: every terminal stays mounted for the life of the app. Leaving a
            // project, switching sections, or browsing the fleet must not tear down a
            // running agent's PTY, so these are inset into the work area and hidden
            // rather than removed.
            terminals
            chrome
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { attentionNotices }
        .onReceive(NotificationCenter.default.publisher(for: AgentNotifications.openSession)) { note in
            guard let id = note.object as? String else { return }
            for project in model.projects {
                if let session = project.sessions.first(where: { $0.id.uuidString == id }) {
                    openAttention(session, in: project)
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1120, minHeight: 680)
        .task { restore() }
        .onChange(of: model.section) { model.openSectionDefault() }
        // The transcript follows the selection rather than the poll: a row that opens an
        // agent must not leave the one before it on screen for up to two seconds under
        // the new agent's name. Every screen that opens one is covered by this — the
        // list column and the overview's "Running now" cards included.
        .onChange(of: model.selection) { model.reloadAgentTranscript() }
    }

    private var attentionNotices: some View {
        VStack(spacing: 0) {
            ForEach(model.projects) { project in
                AttentionNotices(model: model, project: project)
            }
        }
    }

    private func openAttention(_ session: CodeSession, in project: ProjectModel) {
        model.openAttention(session, in: project)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Chrome

    private var terminals: some View {
        ForEach(model.projects) { project in
            ProjectTerminals(
                model: model, project: project,
                leading: Theme.railWidth + (listHidden ? 0 : listWidth))
        }
    }

    @ViewBuilder private var chrome: some View {
        if model.entered == nil {
            ProjectsHome(
                projects: model.projects.map(\.value),
                enter: { if let project = model.project($0.id) { model.enter(project) } },
                create: { creatingProject = true }, add: openProject,
                close: { if let project = model.project($0.id) { close(project) } }
            )
            .sheet(isPresented: $creatingProject) {
                NewProjectForm(
                    parent: projectsParent, create: createProject,
                    cancel: { creatingProject = false })
            }
        } else if let project = model.entered {
            HStack(spacing: 0) {
                // Above the list column: the rail's hover labels hang past its own width.
                Rail(
                    section: $model.section, badges: badges(for: project), leave: { model.leave() },
                    agentCount: project.value.onlineAgentCount,
                    listHidden: listHidden, toggleList: { listHidden.toggle() }
                )
                .zIndex(1)
                if !listHidden {
                    ProjectList(
                        section: model.section, project: project.value, width: listWidth,
                        selection: $model.selection,
                        showDone: model.showDone, changes: project.repo.changes,
                        assign: { assign($0, in: project) },
                        closeSession: { model.close($0, in: project) },
                        remove: { remove($0, in: project) }
                    )
                    .overlay(alignment: .trailing) { listResizer }
                }
                VStack(spacing: 0) {
                    topBar(for: project)
                    screen(for: project)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(isPresented: $addingAgent) {
                NewAgentForm(
                    directory: project.directory,
                    taken: project.snapshot.team.map(\.name),
                    save: { member in
                        do { try Team.write(member, root: project.notebookRoot) } catch {
                            NSAlert(error: error).runModal()
                        }
                        addingAgent = false
                        model.reload()
                    },
                    incubate: { brief in
                        addingAgent = false
                        startIncubation(brief, in: project)
                    },
                    cancel: { addingAgent = false }
                )
            }
        }
    }

    /// The grab area over the list column's trailing divider. It sits in the overlay rather
    /// than the HStack so widening the column does not also move it by its own width.
    private var listResizer: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { $0 ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set() }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let base = dragBase ?? listWidth
                        dragBase = base
                        listWidth = min(560, max(200, base + drag.translation.width))
                    }
                    .onEnded { _ in dragBase = nil }
            )
    }

    /// A dot on the rail for the two things that are about the user rather than the work:
    /// something waiting on them, and something an agent has left to be read.
    private func badges(for project: ProjectModel) -> [ConsoleSection: Color] {
        var badges: [ConsoleSection: Color] = [:]
        if project.snapshot.blocks.contains(where: \.waiting) { badges[.blocks] = Theme.amber }
        if project.sessions.contains(where: { !$0.activeSubagents.isEmpty }) {
            badges[.agents] = Theme.accent
        }
        // Lit for work waiting on the user's approval, not for any edit in the tree.
        if !project.summary.waiting.isEmpty { badges[.review] = Theme.green }
        return badges
    }

    // MARK: - Top bar

    @ViewBuilder private func topBar(for project: ProjectModel) -> some View {
        switch model.section {
        case .overview:
            TopBar(crumbs: [project.name], title: "Overview") {
                providerPicker
                completedToggle
                addMenu(for: project)
                Button {
                    model.section = .board
                    model.selection = .board
                } label: {
                    Label("Assign work", systemImage: "bolt")
                }
                .buttonStyle(.consolePrimary)
            }
        case .board:
            let scoped = model.selection?.card(in: project.snapshot.cards)
            let demo = selectedBlock(in: project).flatMap { $0.isDemo ? $0 : nil }
            TopBar(
                crumbs: demo == nil ? [project.name] : [project.name, "Board"],
                title: scoped?.title ?? demo?.title ?? "Board"
            ) {
                if let demo {
                    NotebookStyle.pill(
                        demo.waiting ? "demo · waiting on you" : "approved",
                        demo.waiting ? Theme.amber : Theme.green, live: demo.waiting)
                }
                if let scoped, scoped.kind == .project { boardProgress(scoped, in: project) }
                completedToggle
                addMenu(for: project)
                Button {
                    startProductReview(in: project)
                } label: {
                    Label("Product review", systemImage: "sparkles")
                }
                .buttonStyle(.console)
            }
        case .agents:
            let watched = model.selectedAgent(in: project) ?? model.selectedSubagent(in: project)?.session
            TopBar(
                crumbs: [project.name],
                title: model.selection == .usage
                    ? "Usage"
                    : model.selectedSubagent(in: project)?.subagent.description
                        ?? watched?.title ?? model.selectedSession(in: project)?.title
                        ?? model.selectedMember(in: project)?.name ?? "Agents"
            ) {
                addMenu(for: project)
                if let watched, model.selectedSubagent(in: project) == nil {
                    let panes = AgentPane.cases(lead: watched.isEngineeringLead)
                    Picker("", selection: agentPane(watched)) {
                        ForEach(panes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .frame(width: panes.count == 3 ? 250 : 175)
                }
                if let found = model.selectedSubagent(in: project) {
                    Button {
                        model.selection = .session(found.session.id)
                    } label: {
                        Label("Parent session", systemImage: "terminal")
                    }
                    .buttonStyle(.console)
                }
            }
        case .review:
            TopBar(crumbs: [project.repo.branch ?? project.name], title: "Review changes") {
                if let head = project.repo.head {
                    Text(head).font(Typo.mono(10.5)).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Button {
                    model.refreshChanges(force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.console)
            }
        case .blocks:
            TopBar(crumbs: [project.name], title: "Blocks") { completedToggle }
        }
    }

    private func boardProgress(_ card: NotebookCard, in project: ProjectModel) -> some View {
        let tasks = project.snapshot.cards.filter { $0.kind == .task && $0.project == card.id }
        let done = tasks.filter { $0.status == "done" }.count
        return HStack(spacing: 9) {
            MeterBar(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count))
                .frame(width: 96)
            Text("\(done)/\(tasks.count)").font(Typo.mono(11)).foregroundStyle(Theme.tx2)
        }
    }

    private var providerPicker: some View {
        Picker("", selection: $agent) {
            ForEach(AgentKind.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 320)
    }

    private var completedToggle: some View {
        Button {
            model.showDone.toggle()
        } label: {
            Label(
                model.showDone ? "Hide completed" : "Completed",
                systemImage: model.showDone ? "eye.slash" : "eye")
        }
        .buttonStyle(.consoleGhost)
    }

    // MARK: - Work area

    @ViewBuilder private func screen(for project: ProjectModel) -> some View {
        if let empty = needsIntake {
            // An empty project has nothing to click, so it asks what it is instead.
            ProjectIntake(project: empty.value) { description in
                addSession(
                    agent, to: empty,
                    prompt: NotebookFormat.onboardingPrompt(description: description),
                    title: "Notebook Setup")
            }
        } else if model.selection == .overview {
            Overview(
                project: project.value, changes: project.repo.changes, head: project.repo.head,
                go: {
                    model.section = $0
                    model.selection = $1
                },
                assign: {
                    model.section = .board
                    model.selection = .board
                })
        } else if model.selection == .board {
            boardView(for: project)
        } else if model.selection == .usage {
            UsageBoard(project: project.value, open: { model.selection = $0 })
        } else if let card = scopedCard(in: project, kind: .project) {
            ProjectDetail(
                card: card, cards: project.snapshot.cards, directory: project.directory,
                assigned: project.assignedTaskIDs, showDone: model.showDone,
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) },
                assign: { tasks in assign(tasks, in: project) },
                run: { card in runServices(card, in: project) },
                openTask: { task in model.selection = .task(task.id) }
            )
            .id(card.id)
        } else if let card = scopedCard(in: project, kind: .task) {
            TaskDetail(
                card: card, cards: project.snapshot.cards, assigned: project.assignedTaskIDs,
                working: workers(on: card.id, in: project),
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) },
                assign: { tasks in assign(tasks, in: project) },
                check: { session, subagent in
                    model.section = .agents
                    model.selection = .subagent(session: session.id, id: subagent.id)
                }
            )
            .id(card.id)
        } else if let card = scopedPageCard(in: project) {
            NotebookEntryDetail(
                card: card, cards: project.snapshot.cards,
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) }
            )
            .id(card.id)
        } else if let watched = model.selectedAgent(in: project) {
            switch model.selection?.pane(of: watched.id) {
            case .lanes:
                EngineeringLeadBoard(
                    session: watched, cards: project.snapshot.cards, blocks: project.snapshot.blocks,
                    team: project.snapshot.team,
                    openTask: {
                        model.section = .board
                        model.selection = .task($0)
                    },
                    openSubagent: { subagent in model.selection = .subagent(session: watched.id, id: subagent.id) },
                    openBlock: {
                        model.section = .blocks
                        model.selection = .block($0.id)
                    }
                )
            case .session:
                // The session's terminal is mounted underneath.
                Color.clear.overlay(alignment: .top) {
                    if let message = model.childNavigation[watched.id] {
                        Text(message).font(Typo.text(12)).padding(10).background(Theme.panel)
                    }
                }
            default:
                SessionTranscript(
                    session: watched, cards: project.snapshot.cards, blocks: project.snapshot.blocks,
                    lines: model.agentTranscript,
                    source: Transcripts.url(of: watched, in: project.directory),
                    openTask: {
                        model.section = .board
                        model.selection = .task($0)
                    },
                    openBlock: {
                        model.section = .blocks
                        model.selection = .block($0.id)
                    },
                    openSubagent: { subagent in model.selection = .subagent(session: watched.id, id: subagent.id) },
                    send: { model.pendingInput[watched.id] = $0 }
                )
            }
        } else if let found = model.selectedSubagent(in: project) {
            Color.clear.overlay(alignment: .top) {
                if let message = model.childNavigation[found.session.id] {
                    Text(message).font(Typo.text(12)).padding(10).background(Theme.panel)
                }
            }
        } else if let member = model.selectedMember(in: project) {
            TeamMemberDetail(
                member: member,
                file: Team.file(for: member.name, root: project.notebookRoot),
                directory: project.directory,
                running: runningAgents(of: member, in: project),
                openSubagent: { session, subagent in
                    model.selection = .subagent(session: session.id, id: subagent.id)
                }
            )
            .id(member.id)
        } else if let block = selectedBlock(in: project), block.isDemo {
            DesignDemo(
                block: block, cards: project.snapshot.cards,
                waiting: project.waitingSession(for: block),
                approve: { revision in approveDemo(block, revision: revision, in: project) },
                revise: { openDesigner(block, in: project) }
            )
            .id(block.id)
        } else if let block = selectedBlock(in: project) {
            BlockDetail(
                block: block, cards: project.snapshot.cards,
                waiting: project.waitingSession(for: block),
                start: { startUnblock(block, in: project) },
                revise: { openProposal(block, approve: false, in: project) },
                resolve: {
                    Blocks.resolve(block)
                    model.reload()
                }
            )
            .id(block.id)
        } else if let task = reviewedTask(in: project) {
            TaskReview(
                task: task, summary: project.summary,
                directory: project.directory, cards: project.snapshot.cards, team: project.snapshot.team,
                branch: project.repo.branch, head: project.repo.head, draft: draft(for: task.id, in: project),
                openFile: { model.selection = .review(file: $0) },
                approve: { approve(task, message: $0, in: project) },
                requestChanges: { requestChanges(on: task, in: project) }
            )
            .id(task.id)
        } else if let path = reviewPath {
            let summary = project.summary
            // A file a task's worker claimed is reviewed as part of that task: comments on
            // its lines join that task's feedback, and the bar is that task's decision.
            let owner = path.isEmpty ? nil : summary.tasks.first { $0.files.contains { $0.path == path } }
            ChangeReview(
                project: project.value, changes: project.repo.changes, head: project.repo.head,
                branch: project.repo.branch,
                path: path, summary: summary,
                select: { model.selection = .review(file: $0) },
                commit: { commit($0, in: project) },
                task: owner, draft: draft(for: owner?.id ?? "", in: project),
                openTask: { model.selection = .reviewTask($0) },
                approve: { message in owner.flatMap { approve($0, message: message, in: project) } },
                requestChanges: { if let owner { requestChanges(on: owner, in: project) } })
        } else if let step = previewStep(in: project) {
            ProjectPreview(
                repo: step.repo, services: step.services,
                run: { runServices([step], in: project) }
            )
            .id(model.selection)
        } else if let entry = selectedEntry {
            NotebookEditor(entry: entry).id(entry.id)
        } else if model.selectedSession(in: project) != nil {
            // The terminal itself is mounted underneath; this pane stays out of its way.
            Color.clear
        } else {
            VStack(spacing: 8) {
                Image(systemName: model.section.systemImage).font(.system(size: 22))
                    .foregroundStyle(Theme.tx4)
                Text("Nothing selected in \(model.section.title).")
                    .font(Typo.text(13)).foregroundStyle(Theme.tx3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        }
    }

    private func boardView(for project: ProjectModel) -> some View {
        NotebookBoard(
            cards: project.snapshot.cards,
            blocks: project.snapshot.blocks,
            assigned: project.assignedTaskIDs,
            showDone: model.showDone,
            assign: { tasks in assign(tasks, in: project) },
            review: { startProductReview(in: project) },
            openCard: { card in model.selection = .task(card.id) },
            openDemo: { demo in model.selection = .block(demo.id) },
            remove: { card in remove(card, in: project) }
        )
    }

    /// Approving a demo is the one gesture that releases the engineering tasks waiting on
    /// a design task: the block is cleared the same way any other is, and the agent that
    /// made it is told which revision won. The app does not touch the task file — the
    /// agent owns that, like every other status in the notebook.
    private func approveDemo(_ block: UserBlock, revision: DemoRevision?, in project: ProjectModel) {
        Blocks.resolve(block)
        if let waiting = project.waitingSession(for: block) {
            let pass = revision.map { " Build \($0.label)." } ?? ""
            model.pendingInput[waiting.id] =
                "The demo at \(block.slug) is approved.\(pass) "
                + "Mark the design task done and start the tasks waiting on it."
            model.section = .agents
            model.selection = .session(waiting.id)
        }
        model.reload()
    }

    /// Saying what is wrong goes to whoever made the demo, in their own transcript. There
    /// is nothing to type on their behalf — the point is that the user says it.
    private func openDesigner(_ block: UserBlock, in project: ProjectModel) {
        guard let waiting = project.waitingSession(for: block) else { return }
        model.section = .agents
        model.selection = .session(waiting.id)
    }

    // MARK: - Selection

    private func agentPane(_ session: CodeSession) -> Binding<AgentPane> {
        Binding(
            get: { model.selection?.pane(of: session.id) ?? .session },
            set: {
                model.selection = .session(session.id, pane: $0)
                model.reloadAgentTranscript()
            }
        )
    }

    /// A project with no notebook and no agent yet — the one case that starts a chat.
    private var needsIntake: ProjectModel? {
        model.entered.flatMap { $0.hasNotebook || !$0.sessions.isEmpty ? nil : $0 }
    }

    private var selectedEntry: NotebookEntry? {
        guard case .entry(let id) = model.selection, let project = model.entered else { return nil }
        return NotebookLoader.find(id, in: project.snapshot.entries)
    }

    private func scopedCard(in project: ProjectModel, kind: EntryKind) -> NotebookCard? {
        let id: String
        switch (model.selection, kind) {
        case (.project(let scoped)?, .project), (.task(let scoped)?, .task): id = scoped
        default: return nil
        }
        return project.snapshot.cards.first { $0.id == id && $0.kind == kind }
    }

    private func scopedPageCard(in project: ProjectModel) -> NotebookCard? {
        guard case .page(let id) = model.selection else { return nil }
        return project.snapshot.cards.first { $0.id == id }
    }

    /// The agents running this member's skill right now, wherever they were dispatched
    /// from — the way back from a standing agent into the work it is doing.
    private func runningAgents(
        of member: TeamMember,
        in project: ProjectModel
    ) -> [(session: CodeSession, subagent: SubagentStatus)] {
        project.sessions.flatMap { session in
            session.activeSubagents.filter { $0.member == member.name }
                .map { (session: session, subagent: $0) }
        }
    }

    /// Every subagent in this project that was dispatched for one task, whichever lead
    /// spawned it. The link is the subagent's own name, matched when it is read off disk.
    private func workers(on taskID: String, in project: ProjectModel) -> [(CodeSession, SubagentStatus)] {
        project.sessions.flatMap { session in
            session.subagents.filter { $0.taskID == taskID }.map { (session, $0) }
        }
    }

    private func selectedBlock(in project: ProjectModel) -> UserBlock? {
        project.snapshot.blocks.first { model.selection == .block($0.id) }
    }

    /// The file a review selection points at, or "" for the review screen with nothing
    /// picked yet. Nil when the selection is not a review at all.
    private var reviewPath: String? {
        guard case .review(let file) = model.selection else { return nil }
        return file ?? ""
    }

    // MARK: - Assigning

    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// list and the board cannot disagree about what a batch is. Also the one place that
    /// excludes work a still-open lead session already has, so a task never goes to two
    /// leads at once.
    ///
    /// A lead that is still running is talked to, not duplicated: the new batch is typed
    /// into its own terminal as a follow-up message, the same as telling a person who is
    /// already working "also pick these up" rather than hiring a second lead.
    private func assign(_ tasks: [NotebookCard], in project: ProjectModel) {
        let batch = NotebookIndex.withBlockers(
            tasks, in: project.snapshot.cards, excluding: project.assignedTaskIDs)
        guard !batch.isEmpty else {
            guard !tasks.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "Nothing to assign"
            alert.informativeText =
                "Every task here is already done, or already has an Engineering "
                + "Lead on it — wait for that session to finish, or close it, before assigning again."
            alert.runModal()
            return
        }
        model.section = .agents
        if let lead = project.sessions.first(where: { $0.isEngineeringLead && !$0.exited }) {
            let leadAgent = lead.agent ?? .claude
            project.appendTaskIDs(batch.map(\.id), to: lead.id)
            model.pendingInput[lead.id] = NotebookFormat.additionalTasksPrompt(
                tasks: batch, sessionID: lead.id,
                agent: leadAgent)
            model.selection = .session(lead.id)
            return
        }
        // The id is minted here so the prompt can carry it: a lead that knows its own
        // session id can write it into any block it raises, and the answer comes back here.
        let id = UUID()
        addSession(
            agent, id: id, to: project,
            prompt: NotebookFormat.engineeringPrompt(tasks: batch, sessionID: id, agent: agent),
            title: "Engineering Lead", taskIDs: batch.map(\.id))
    }

    private func addMenu(for project: ProjectModel) -> some View {
        Menu {
            Section("Session") {
                Button(agent.displayName, systemImage: agent.systemImage) {
                    addSession(agent, to: project)
                    model.section = .agents
                }
            }
            Section("Team") {
                Button("Agent…", systemImage: "person.badge.plus") { addingAgent = true }
                    .disabled(!project.hasNotebook)
            }
            Section("Notebook") {
                Button("Roadmap Entry…", systemImage: "map") { add(.roadmap, to: project) }
                Button("Project…", systemImage: "shippingbox") { add(.project, to: project) }
                Button("Task…", systemImage: "checkmark.circle") { add(.task, to: project) }
                Button("Memory…", systemImage: "brain") { add(.memory, to: project) }
                    .disabled(notebookProject(in: project) == nil)
            }
            Divider()
            Button("Describe New Feature…", systemImage: "text.bubble") {
                startProduct("describe", in: project)
            }
            .disabled(!project.hasNotebook)
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.directory])
            }
            Button("Close Project", systemImage: "xmark") { close(project) }
        } label: {
            Label("New", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 62)
    }

    // MARK: - Blocks

    /// A gate starts a session whose only job is unblocking it. A proposal instead returns
    /// to its Product transcript, and only a ready proposal's create button sends approval.
    ///
    /// The page is deliberately not opened here. A browser tab that appears before the
    /// session has said anything lands the user on a token screen with no idea what it is
    /// for; the engineer explains first, and opens the page when the user is ready for it.
    private func startUnblock(_ block: UserBlock, in project: ProjectModel) {
        guard !block.isProposal else {
            return openProposal(block, approve: block.proposalReady, in: project)
        }
        addSession(
            agent, to: project, prompt: NotebookFormat.unblockPrompt(block: block, agent: agent),
            title: "Unblock \(block.title)")
        model.section = .agents
    }

    /// A proposal belongs to the Product conversation that shaped it. Opening it is only
    /// navigation; the ready proposal's explicit create action is the approval message.
    private func openProposal(_ block: UserBlock, approve: Bool, in project: ProjectModel) {
        let running =
            block.session.flatMap { id in
                project.sessions.first { $0.id == id && !$0.exited }
            } ?? project.sessions.last { isProduct($0) && !$0.exited }
        if let running {
            model.section = .agents
            model.selection = .session(running.id)
            if approve {
                model.pendingInput[running.id] =
                    "Approved. Create the roadmap changes, project, and tasks in this ready proposal."
            }
            return
        }
        let decision = approve ? "\nDecision: approve" : ""
        startProduct(NotebookFormat.relativePath(block.url) + decision, in: project)
    }

    // MARK: - Projects

    private func openProject() {
        guard
            let path = pickDirectory(
                message: "Agents run in this folder and its notebook lives in \(NotebookFormat.folderName)/."
            )
        else { return }
        let directory = URL(fileURLWithPath: path)
        if let existing = model.project(at: directory) {
            model.enter(existing)
            return
        }
        let project = model.open(directory)
        persist()
        model.enter(project)
    }

    /// Where a described project lands when its prompt names nowhere: beside the ones
    /// already open, since that is where this person keeps projects, and `~/Projects` on
    /// a first run. Created on the way, so nothing has to be picked in a panel first.
    private var projectsParent: URL {
        model.projects.last.map { $0.directory.deletingLastPathComponent() }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects")
    }

    /// A project described rather than opened: the folder is new and empty, so the prompt
    /// that named it goes straight to the session that writes its notebook — the intake
    /// screen has nothing left to ask.
    private func createProject(at directory: URL, prompt: String) {
        creatingProject = false
        if let existing = model.project(at: directory) {
            model.enter(existing)
            return
        }
        let project = model.open(directory)
        persist()
        model.enter(project)
        guard let started = model.entered, !started.hasNotebook else { return }
        model.section = .agents
        addSession(
            agent, to: started,
            prompt: NotebookFormat.onboardingPrompt(description: prompt),
            title: "Notebook Setup")
    }

    private func restore() {
        guard model.projects.isEmpty else { return }
        if CommandLine.arguments.contains("--attention-selftest") {
            runAttentionSelfTest()
            return
        }
        model.restore(openProjects)
        persist()
        model.reload()
    }

    /// Full app regression: actual Codex screen bytes travel through the PTY,
    /// representable callback, app state, banner and session navigation. No real agent.
    private func runAttentionSelfTest() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yk-attention-\(UUID())")
        let root = NotebookFormat.root(in: directory)
        _ = try! NotebookFormat.create(.task, title: "Trust screen test", in: root, project: nil)
        let output = directory.appendingPathComponent("trust.ansi")
        // Dev-only, run from a checkout: the capture is the test fixture, not a copy of it.
        let capture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Tests/YongkangCoreTests/Fixtures/codex/codex-0.154.0-trust-screen.ansi")
        try! FileManager.default.copyItem(at: capture, to: output)
        let project = model.open(directory)
        let session = CodeSession(
            title: "Engineering Lead", icon: "terminal",
            line: "cat \(AgentCommand.quoted(output.path)); exec sleep 30", agent: .codex)
        project.addSession(
            id: session.id, title: session.title, icon: session.icon, line: session.line, agent: session.agent)
        model.enter(project)
        model.section = .agents
        model.selection = .session(session.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            precondition(model.attention[session.id] != nil, "PTY callback must reach the app's banner state")
            guard let host = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
            else {
                preconditionFailure("attention selftest needs a rendered app window")
            }
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "/tmp/yongkang-attention-selftest.png"))
            openAttention(session, in: project)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                precondition(model.isVisible(session), "Open session must reveal the blocked terminal")
                func stop(_ view: NSView) {
                    if let terminal = view as? AttentionTerminalView { terminal.terminate() }
                    view.subviews.forEach(stop)
                }
                stop(host)
                try? FileManager.default.removeItem(at: directory)
                print("attention app selftest ok — banner rendered and blocked session opened")
                exit(0)
            }
        }
    }

    private func persist() {
        openProjects = model.storedProjects
    }

    private func close(_ project: ProjectModel) {
        model.close(project)
        persist()
    }

    /// Product looks at the whole product and discusses what should come next. Blocks gets
    /// one link back to that transcript, then the finalized plan; the board stays unchanged
    /// until the user explicitly creates it.
    private func startProductReview(in project: ProjectModel) {
        startProduct("review", in: project)
    }

    /// One product voice per project. A second session would propose against a board the
    /// first one is already rewriting, so a running one is talked to instead — the same
    /// rule the Engineering Lead follows for a second batch.
    private func startProduct(_ arguments: String, in project: ProjectModel) {
        model.section = .agents
        if let running = project.sessions.first(where: { isProduct($0) && !$0.exited }) {
            let productAgent = running.agent ?? .claude
            model.pendingInput[running.id] = NotebookFormat.productPrompt(
                arguments: arguments, sessionID: running.id, agent: productAgent
            )
            model.selection = .session(running.id)
            return
        }
        let id = UUID()
        addSession(
            agent, id: id, to: project,
            prompt: NotebookFormat.productPrompt(arguments: arguments, sessionID: id, agent: agent),
            title: "Product")
    }

    /// Incubate mode: the app does not write the agent, a session does. It searches the
    /// skills this project can already load, fetches or writes what is missing, and adds
    /// the file to `.notebook/team/` — which the poll picks up as a new roster row, the
    /// same way any other notebook entry an agent writes turns up.
    private func startIncubation(_ brief: String, in project: ProjectModel) {
        model.section = .agents
        addSession(
            agent, to: project,
            prompt: NotebookFormat.incubatePrompt(brief: brief, agent: agent),
            title: "New Agent")
    }

    private func isProduct(_ session: CodeSession) -> Bool {
        session.title == "Product" || session.title.hasPrefix("Product ")
    }

    /// The repo a preview route points at, one per repo actually on disk, deduped across
    /// every notebook project. Nil if `selection` is not a preview.
    private func previewStep(
        in project: ProjectModel
    )
        -> (repo: String, directory: URL, services: [Service.Runnable])?
    {
        guard case .preview(let directory) = model.selection else { return nil }
        let steps = project.snapshot.cards.filter { $0.kind == .project }
            .flatMap { Service.plan(for: $0, in: project.directory) }
        return Service.dedupedByDirectory(steps).first { $0.directory.path == directory.path }
    }

    // MARK: - Review

    private func reviewedTask(in project: ProjectModel) -> SummaryTask? {
        guard case .reviewTask(let id) = model.selection else { return nil }
        return project.summary.tasks.first { $0.id == id }
    }

    private func draft(for taskID: String, in project: ProjectModel) -> Binding<ReviewDraft> {
        Binding(
            get: { project.reviewDrafts[taskID] ?? ReviewDraft() },
            set: { project.reviewDrafts[taskID] = $0 == ReviewDraft() ? nil : $0 })
    }

    /// Approving is committing: only this task's files and its records, then on to the
    /// next task waiting. Nothing is sent to the lead — it already marked the task done.
    private func approve(_ task: SummaryTask, message: String, in project: ProjectModel) -> String? {
        let failure = GitChanges.commit(message: message, paths: task.commitPaths, in: project.directory)
        model.refreshChanges(force: true)
        guard failure == nil else { return failure }
        project.reviewDrafts[task.id] = nil
        model.selection = project.firstReview
        return nil
    }

    /// Sending a task back goes to the lead that holds it, typed into its terminal like any
    /// follow-up; with no lead running, a fresh one starts with the task and the comments.
    private func requestChanges(on task: SummaryTask, in project: ProjectModel) {
        guard let draft = project.reviewDrafts[task.id], !draft.isEmpty else { return }
        let message = draft.message(taskID: task.id, title: task.title)
        let leads = project.sessions.filter { $0.isEngineeringLead && !$0.exited }
        if let lead = leads.first(where: { $0.taskIDs.contains(task.id) }) ?? leads.first {
            if !lead.taskIDs.contains(task.id) { project.appendTaskIDs([task.id], to: lead.id) }
            project.reviewDrafts[task.id] = nil
            model.section = .agents
            model.pendingInput[lead.id] = message
            model.selection = .session(lead.id)
            return
        }
        guard let card = project.snapshot.cards.first(where: { $0.id == task.id }) else { return }
        project.reviewDrafts[task.id] = nil
        model.section = .agents
        let id = UUID()
        addSession(
            agent, id: id, to: project,
            prompt: NotebookFormat.changeRequestPrompt(task: card, message: message, sessionID: id, agent: agent),
            title: "Engineering Lead", taskIDs: [task.id])
    }

    /// The review screen's one write to the repo. Staging and committing is all it does —
    /// no push, no merge, no branch — and only because the user pressed the button.
    private func commit(_ message: String, in project: ProjectModel) -> String? {
        let failure = GitChanges.commit(message: message, in: project.directory)
        if failure == nil { model.selection = .review(file: nil) }
        model.refreshChanges(force: true)
        return failure
    }

    // MARK: - Sessions

    /// `id` is generated up front so the same id names both the CLI's `--session-id` and
    /// this session's own row — that is what lets its transcript be found again later, and
    /// what a caller passes in when the prompt itself has to name the session.
    private func addSession(
        _ agent: AgentKind, id: UUID = UUID(), to project: ProjectModel,
        prompt: String? = nil, title: String? = nil, taskIDs: [String] = []
    ) {
        addSession(
            id: id, to: project, title: title ?? agent.displayName, icon: agent.systemImage,
            line: AgentCommand.line(
                directory: project.directory.path,
                agent: agent, prompt: prompt, sessionID: id,
                brief: title?.hasPrefix("Engineering Lead") == true,
                noCommit: title?.hasPrefix("Engineering Lead") == true),
            agent: agent, taskIDs: taskIDs)
    }

    private func addSession(
        id: UUID = UUID(), to project: ProjectModel, title: String, icon: String, line: String,
        agent: AgentKind? = nil, taskIDs: [String] = []
    ) {
        project.addSession(id: id, title: title, icon: icon, line: line, agent: agent, taskIDs: taskIDs)
        // New sessions open their live CLI.
        model.selection = .session(id)
    }

    /// Every service in a project's repos, started at once — the board's "run the whole
    /// project" action.
    private func runServices(_ card: NotebookCard, in project: ProjectModel) {
        runServices(Service.plan(for: card, in: project.directory), in: project)
    }

    /// One terminal per runnable service, all started together, because a front end
    /// reviewed without its service behind it is a page of errors. A service named after
    /// its repo (the common single-app case) keeps that name; one of several under a repo
    /// is named `repo/service`. Anything with nothing to run is named rather than skipped
    /// in silence.
    ///
    /// A service already running is shown, not started again: a second `npm run dev`
    /// fights the first one for its port, and the loser exits — which is exactly what was
    /// pushing a "default to :3000" preview onto whatever port the collision left it on.
    private func runServices(
        _ steps: [(repo: String, directory: URL, services: [Service.Runnable])],
        in project: ProjectModel
    ) {
        let named = steps.flatMap { step in
            step.services.map { service in
                (
                    label: service.name == step.repo ? step.repo : "\(step.repo)/\(service.name)",
                    directory: service.directory, command: service.command
                )
            }
        }
        model.section = .agents
        for service in named where service.command != nil {
            let title = "Run \(service.label)"
            if let running = project.sessions.first(where: { $0.title == title }) {
                model.selection = .session(running.id)
                continue
            }
            addSession(
                to: project, title: title, icon: "play.circle",
                line: AgentCommand.line(directory: service.directory.path, run: service.command!))
        }
        let stuck = named.filter { $0.command == nil }
        guard !stuck.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = named.count == stuck.count ? "Nothing to run yet" : "Some services did not start"
        alert.informativeText = """
            No start command found in: \(stuck.map(\.label).joined(separator: ", ")).

            A service starts if it has a compose file, an npm dev/start script, Cargo.toml, \
            go.mod, or a Makefile dev target. Add `repos: [path, ...]` to the project's \
            frontmatter to point at the folders that do, or split a repo that holds more than \
            one app into `apps/` or `services/` subfolders so each is found on its own.
            """
        alert.runModal()
    }

    // MARK: - Notebook entries

    /// The `.notebook/projects/<id>` the selection sits in — memory has to land in one.
    private func notebookProject(in project: ProjectModel) -> String? {
        if case .project(let scope) = model.selection { return scope }
        if case .task(let id) = model.selection,
            let owner = project.snapshot.cards.first(where: { $0.id == id })?.project
        {
            return owner
        }
        guard case .entry(let path) = model.selection,
            path.hasPrefix(NotebookEntry.id(for: project.directory)),
            let marker = path.range(of: "/\(NotebookFormat.folderName)/projects/")
        else { return nil }
        return path[marker.upperBound...].split(separator: "/").first.map(String.init)
    }

    private func add(_ kind: EntryKind, to project: ProjectModel) {
        guard let title = askTitle(kind) else { return }
        do {
            let file = try NotebookFormat.create(
                kind, title: title, in: project.notebookRoot,
                project: notebookProject(in: project),
                roadmap: notebookRoadmap(in: project),
                subject: notebookSubject(in: project))
            model.reload()
            let id =
                kind == .project
                ? file.deletingLastPathComponent().lastPathComponent
                : file.deletingPathExtension().lastPathComponent
            model.section = .board
            switch kind {
            case .project: model.selection = .project(id)
            case .task: model.selection = .task(id)
            case .roadmap, .memory, .run: model.selection = .page(id)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Removing a notebook entry. A project takes its tasks with it — a task filed under
    /// an id that no longer exists shows up nowhere and would never be worked.
    private func remove(_ card: NotebookCard, in project: ProjectModel) {
        // The board the user asked from: the poll keeps running under the alert below.
        let cards = project.snapshot.cards
        let tasks = NotebookFormat.owned(by: card, in: cards).count - 1
        let alert = NSAlert()
        alert.messageText = "Move \u{201C}\(card.title)\u{201D} to the Trash?"
        alert.informativeText =
            card.kind == .project
            ? "The project folder, its memory and its \(tasks) task\(tasks == 1 ? "" : "s") go with it. "
                + "You can put them back from the Trash."
            : "You can put it back from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try NotebookFormat.remove(card, in: cards)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        // Anything on screen that was inside what just went to the Trash has no page left.
        let gone = Set(NotebookFormat.owned(by: card, in: cards).map(\.path))
        if let shown = model.selection?.card(in: cards),
            gone.contains(where: { shown.url.path == $0 || shown.url.path.hasPrefix($0 + "/") })
        {
            model.selection = .board
        }
        model.reload()
    }

    private func notebookRoadmap(in project: ProjectModel) -> String? {
        if case .page(let id) = model.selection,
            project.snapshot.cards.contains(where: { $0.id == id && $0.kind == .roadmap })
        {
            return id
        }
        let roadmaps = project.snapshot.cards.filter { $0.kind == .roadmap }
        return roadmaps.count == 1 ? roadmaps[0].id : nil
    }

    private func notebookSubject(in project: ProjectModel) -> String? {
        model.selection?.cardID ?? notebookProject(in: project)
    }
}

/// One project's terminals, in their own view so a poll that changes this project's
/// sessions re-renders its terminals and not the window around them.
private struct ProjectTerminals: View {
    let model: AppModel
    let project: ProjectModel
    /// Past the rail and the list column, into the work area.
    let leading: CGFloat

    var body: some View {
        ForEach(project.sessions) { session in
            // Read here as well as through the binding, so text queued for this session
            // re-renders its terminal even when nothing else about it changed.
            let _ = model.pendingInput[session.id]
            AgentTerminal(
                line: session.line, label: session.title,
                pending: Binding(
                    get: { model.pendingInput[session.id] }, set: { model.pendingInput[session.id] = $0 }),
                onExit: { model.markExited(session, in: project) },
                onAttention: { reason in
                    guard session.agent != nil else { return }
                    model.attentionChanged(reason, session: session, project: project)
                }, focused: model.isVisible(session), agent: session.agent,
                child: model.isVisible(session) ? model.selectedSubagent(in: project)?.subagent : nil,
                onChildNavigation: { message in
                    if model.childNavigation[session.id] != message { model.childNavigation[session.id] = message }
                }
            )
            .padding(.leading, leading)
            .padding(.top, Theme.topBarHeight)
            .opacity(model.isVisible(session) ? 1 : 0)
            .allowsHitTesting(model.isVisible(session))
            .accessibilityHidden(!model.isVisible(session))
        }
    }
}

/// One project's "Action required" notices, in their own view for the same reason as
/// `ProjectTerminals`.
private struct AttentionNotices: View {
    let model: AppModel
    let project: ProjectModel

    var body: some View {
        ForEach(project.sessions.filter { model.attention[$0.id] != nil && !$0.exited }) { session in
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Action required · \(project.name) · \(session.title)").font(Typo.text(12, .medium))
                    Text(model.attention[session.id] ?? "").font(Typo.text(11)).foregroundStyle(Theme.tx2)
                }
                Spacer()
                Button("Open session") {
                    model.openAttention(session, in: project)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.consolePrimary)
            }
            .padding(14)
            .background(Theme.panel)
        }
    }
}

func pickDirectory(message: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = message
    return panel.runModal() == .OK ? panel.url?.path : nil
}

private func askTitle(_ kind: EntryKind) -> String? {
    let alert = NSAlert()
    alert.messageText = "New \(kind.displayName)"
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = "Title"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
}
