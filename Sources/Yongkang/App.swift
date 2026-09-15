import SwiftUI
import AppKit
import Combine

@main
struct YongkangApp: App {
    // ponytail: no folder is touched until the user picks one. Defaulting to $HOME made
    // claude scan the home folder and trip every TCC prompt (iCloud Drive, Music,
    // Documents) at launch. An NSOpenPanel choice carries intent, so macOS grants it.
    @State private var projects: [Project] = []
    /// nil = the all-projects screen; otherwise the project you are inside.
    @State private var entered: UUID?
    /// Which of the rail's sections the window is showing. The list column is that
    /// section's objects and the work area is whichever one is selected.
    @State private var section: ConsoleSection = .overview
    /// Notebook entries tag by file path, terminals by UUID, everything else by `Tag`.
    @State private var selection: String?
    /// Progress or a fallback instruction while selecting a child inside its CLI.
    @State private var childNavigation: [UUID: String] = [:]
    @State private var attention: [UUID: String] = [:]
    @State private var pendingInput: [UUID: String] = [:]
    /// The lines of whichever agent `selection` currently points at — a subagent, or the
    /// lead itself. Kept apart from `CodeSession.subagents`, which only ever holds each
    /// one's status, because reading and parsing a whole transcript is only worth doing
    /// for the one actually on screen.
    @State private var agentTranscript: [TranscriptLine] = []
    /// The file those lines came from, so switching agents replaces them rather than
    /// leaving one agent's work under another's name when the two are the same length.
    @State private var transcriptSource: URL?
    /// What the agents changed on disk, read from git. Only refreshed while a screen that
    /// shows it is open — a repo-wide diff every two seconds would be rude.
    @State private var changes: [FileChange] = []
    /// What the user has written about each task under review, by task id, until they send
    /// it or approve. Lives here rather than in the page so leaving for a diff keeps it.
    @State private var reviewDrafts: [String: ReviewDraft] = [:]
    @State private var head: String?
    @State private var branch: String?
    @State private var ticks = 0
    /// The list width the current resize drag started from; nil when nothing is dragging.
    @State private var dragBase: Double?
    /// Completed notebook work is historical noise until the user asks for it.
    @State private var showDone = false
    /// The done tasks the window has already seen in this project. nil until the first
    /// poll seeds it, so opening a project full of finished work does not read as news.
    @State private var doneTasks: Set<String>?
    /// The "New → Agent…" sheet, adding one file to `.notebook/team/`.
    @State private var addingAgent = false
    /// The new-project sheet, opened from the Fleet page's own tile: a prompt, which is
    /// also what says where its folder goes.
    @State private var creatingProject = false
    /// Blocks already reported back to the session that was waiting, so a cleared block
    /// says so once rather than on every 2-second poll.
    @State private var deliveredBlocks: Set<String> = []
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

    // ponytail: poll instead of an FSEvents watcher. The agents in the console write
    // these files while you watch them; re-listing a few dozen paths every 2s is less
    // code than a recursive watcher and the tree is tiny. Revisit at thousands of files.
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            NotebookSelfTest.run()
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--shots"),
           let path = CommandLine.arguments[safe: index + 1] {
            DesignShots.run(into: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
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
                for project in projects {
                    if let session = project.sessions.first(where: { $0.id.uuidString == id }) {
                        openAttention(session, in: project)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .frame(minWidth: 1120, minHeight: 680)
            .task { restore() }
            .onReceive(tick) { _ in reload() }
            .onChange(of: section) { _ in openSectionDefault() }
            // The transcript follows the selection rather than the poll: a row that opens an
            // agent must not leave the one before it on screen for up to two seconds under
            // the new agent's name. Every screen that opens one is covered by this — the
            // list column and the overview's "Running now" cards included.
            .onChange(of: selection) { _ in reloadAgentTranscript() }
        }
        .windowToolbarStyle(.unified)
    }

    private var attentionNotices: some View {
        VStack(spacing: 0) {
            ForEach(projects) { project in
                ForEach(project.sessions.filter { attention[$0.id] != nil && !$0.exited }) { session in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(Theme.amber)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Action required · \(project.name) · \(session.title)").font(Typo.text(12, .medium))
                            Text(attention[session.id] ?? "").font(Typo.text(11)).foregroundStyle(Theme.tx2)
                        }
                        Spacer()
                        Button("Open session") { openAttention(session, in: project) }
                            .buttonStyle(.consolePrimary)
                    }
                    .padding(14)
                    .background(Theme.panel)
                }
            }
        }
    }

    private func attentionChanged(_ reason: String?, session: CodeSession, project: Project) {
        if reason != nil {
            guard projects.contains(where: { $0.id == project.id && $0.sessions.contains(where: {
                $0.id == session.id && !$0.exited
            }) }) else { return }
        }
        guard attention[session.id] != reason else { return }
        attention[session.id] = reason
        if let reason {
            guard !CommandLine.arguments.contains("--attention-selftest") else { return }
            AgentNotifications.shared.send(sessionID: session.id,
                                             title: "\(project.name) · \(session.title)", reason: reason)
        } else {
            AgentNotifications.shared.clear(session.id)
        }
    }

    private func openAttention(_ session: CodeSession, in project: Project) {
        if entered != project.id { enter(project) }
        section = .agents
        selection = Tag.session(session)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var enteredProject: Project? { projects.first { $0.id == entered } }

    // MARK: - Chrome

    private var terminals: some View {
        ForEach(projects) { project in
            ForEach(project.sessions) { session in
                AgentTerminal(line: session.line, label: session.title,
                              pending: pendingBinding(session),
                              onExit: { markExited(session, in: project) },
                              onAttention: { reason in
                                  guard session.agent != nil else { return }
                                  attentionChanged(reason, session: session, project: project)
                              }, focused: isVisible(session), agent: session.agent,
                              child: isVisible(session) ? selectedSubagent(in: project)?.subagent : nil,
                              onChildNavigation: { message in
                                  if childNavigation[session.id] != message { childNavigation[session.id] = message }
                              })
                    .padding(.leading, Theme.railWidth + (listHidden ? 0 : listWidth))
                    .padding(.top, Theme.topBarHeight)
                    .opacity(isVisible(session) ? 1 : 0)
                    .allowsHitTesting(isVisible(session))
                    .accessibilityHidden(!isVisible(session))
            }
        }
    }

    @ViewBuilder private var chrome: some View {
        if entered == nil {
            ProjectsHome(projects: projects, enter: enter,
                         create: { creatingProject = true }, add: openProject, close: close)
                .sheet(isPresented: $creatingProject) {
                    NewProjectForm(parent: projectsParent, create: createProject,
                                   cancel: { creatingProject = false })
                }
        } else if let project = enteredProject {
            HStack(spacing: 0) {
                // Above the list column: the rail's hover labels hang past its own width.
                Rail(section: $section, badges: badges(for: project), leave: leave,
                     agentCount: project.onlineAgentCount,
                     listHidden: listHidden, toggleList: { listHidden.toggle() })
                    .zIndex(1)
                if !listHidden {
                    ProjectList(section: section, project: project, width: listWidth,
                                selection: $selection,
                                showDone: showDone, changes: changes,
                                assign: { assign($0, in: project) },
                                closeSession: { close($0, in: project) },
                                remove: { remove($0, in: project) })
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
                    taken: project.team.map(\.name),
                    save: { member in
                        do { try Team.write(member, root: project.notebookRoot) }
                        catch { NSAlert(error: error).runModal() }
                        addingAgent = false
                        reload()
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
    private func badges(for project: Project) -> [ConsoleSection: Color] {
        var badges: [ConsoleSection: Color] = [:]
        if project.blocks.contains(where: \.waiting) { badges[.blocks] = Theme.amber }
        if project.sessions.contains(where: { !$0.activeSubagents.isEmpty }) {
            badges[.agents] = Theme.accent
        }
        // Lit for work waiting on the user's approval, not for any edit in the tree.
        if !ChangeSummary.of(project, changes: changes).waiting.isEmpty { badges[.review] = Theme.green }
        return badges
    }

    // MARK: - Top bar

    @ViewBuilder private func topBar(for project: Project) -> some View {
        switch section {
        case .overview:
            TopBar(crumbs: [project.name], title: "Overview") {
                providerPicker
                completedToggle
                addMenu(for: project)
                Button { section = .board; selection = Tag.board(project) } label: {
                    Label("Assign work", systemImage: "bolt")
                }
                .buttonStyle(.consolePrimary)
            }
        case .board:
            let scoped = Tag.card(selection, in: project.cards)
            let demo = selectedBlock(in: project).flatMap { $0.isDemo ? $0 : nil }
            TopBar(crumbs: demo == nil ? [project.name] : [project.name, "Board"],
                   title: scoped?.title ?? demo?.title ?? "Board") {
                if let demo {
                    NotebookStyle.pill(demo.waiting ? "demo · waiting on you" : "approved",
                                       demo.waiting ? Theme.amber : Theme.green, live: demo.waiting)
                }
                if let scoped, scoped.kind == .project { boardProgress(scoped, in: project) }
                completedToggle
                addMenu(for: project)
                Button { startProductReview(in: project) } label: {
                    Label("Product review", systemImage: "sparkles")
                }
                .buttonStyle(.console)
            }
        case .agents:
            let watched = selectedAgent(in: project) ?? selectedSubagent(in: project)?.session
            TopBar(crumbs: [project.name],
                   title: selection == Tag.usage(project) ? "Usage"
                        : selectedSubagent(in: project)?.subagent.description
                        ?? watched?.title ?? selectedSession(in: project)?.title
                        ?? selectedMember(in: project)?.name ?? "Agents") {
                addMenu(for: project)
                if let watched, selectedSubagent(in: project) == nil {
                    let panes = AgentPane.cases(lead: watched.isEngineeringLead)
                    Picker("", selection: agentPane(watched)) {
                        ForEach(panes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .frame(width: panes.count == 3 ? 250 : 175)
                }
                if let found = selectedSubagent(in: project) {
                    Button { selection = Tag.session(found.session) } label: {
                        Label("Parent session", systemImage: "terminal")
                    }
                    .buttonStyle(.console)
                }
            }
        case .review:
            TopBar(crumbs: [branch ?? project.name], title: "Review changes") {
                if let head {
                    Text(head).font(Typo.mono(10.5)).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Button { refreshChanges(force: true) } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.console)
            }
        case .blocks:
            TopBar(crumbs: [project.name], title: "Blocks") { completedToggle }
        }
    }

    private func boardProgress(_ card: NotebookCard, in project: Project) -> some View {
        let tasks = project.cards.filter { $0.kind == .task && $0.project == card.id }
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
        Button { showDone.toggle() } label: {
            Label(showDone ? "Hide completed" : "Completed",
                  systemImage: showDone ? "eye.slash" : "eye")
        }
        .buttonStyle(.consoleGhost)
    }

    // MARK: - Work area

    @ViewBuilder private func screen(for project: Project) -> some View {
        if let empty = needsIntake {
            // An empty project has nothing to click, so it asks what it is instead.
            ProjectIntake(project: empty) { description in
                addSession(agent, to: empty,
                           prompt: NotebookFormat.onboardingPrompt(description: description),
                           title: "Notebook Setup")
            }
        } else if selection == Tag.overview(project) {
            Overview(project: project, changes: changes, head: head,
                     go: { section = $0; if let tag = $1 { selection = tag } },
                     assign: { section = .board; selection = Tag.board(project) })
        } else if selection == Tag.board(project) {
            boardView(for: project)
        } else if selection == Tag.usage(project) {
            UsageBoard(project: project, open: { selection = $0 })
        } else if let card = scopedCard(in: project, kind: .project) {
            ProjectDetail(
                card: card, cards: project.cards, directory: project.directory,
                assigned: project.assignedTaskIDs, showDone: showDone,
                open: { url in selection = NotebookEntry.id(for: url) },
                assign: { tasks in assign(tasks, in: project) },
                run: { card in runServices(card, in: project) },
                openTask: { task in selection = Tag.task(task.id) }
            )
            .id(card.id)
        } else if let card = scopedCard(in: project, kind: .task) {
            TaskDetail(
                card: card, cards: project.cards, assigned: project.assignedTaskIDs,
                working: workers(on: card.id, in: project),
                open: { url in selection = NotebookEntry.id(for: url) },
                assign: { tasks in assign(tasks, in: project) },
                check: { session, subagent in
                    section = .agents
                    selection = Tag.subagent(session, subagent)
                }
            )
            .id(card.id)
        } else if let card = scopedPageCard(in: project) {
            NotebookEntryDetail(card: card, cards: project.cards,
                                open: { url in selection = NotebookEntry.id(for: url) })
                .id(card.id)
        } else if let watched = selectedAgent(in: project) {
            switch AgentPane.of(selection, session: watched.id) {
            case .lanes:
                EngineeringLeadBoard(
                    session: watched, cards: project.cards, blocks: project.blocks,
                    team: project.team,
                    openTask: { section = .board; selection = Tag.task($0) },
                    openSubagent: { subagent in selection = Tag.subagent(watched, subagent) },
                    openBlock: { section = .blocks; selection = Tag.block($0) }
                )
            case .session:
                // The session's terminal is mounted underneath.
                Color.clear.overlay(alignment: .top) {
                    if let message = childNavigation[watched.id] {
                        Text(message).font(Typo.text(12)).padding(10).background(Theme.panel)
                    }
                }
            default:
                SessionTranscript(
                    session: watched, cards: project.cards, blocks: project.blocks,
                    lines: agentTranscript,
                    source: Transcripts.url(of: watched, in: project.directory),
                    openTask: { section = .board; selection = Tag.task($0) },
                    openBlock: { section = .blocks; selection = Tag.block($0) },
                    openSubagent: { subagent in selection = Tag.subagent(watched, subagent) },
                    send: { pendingInput[watched.id] = $0 }
                )
            }
        } else if let found = selectedSubagent(in: project) {
            Color.clear.overlay(alignment: .top) {
                if let message = childNavigation[found.session.id] {
                    Text(message).font(Typo.text(12)).padding(10).background(Theme.panel)
                }
            }
        } else if let member = selectedMember(in: project) {
            TeamMemberDetail(
                member: member,
                file: Team.file(for: member.name, root: project.notebookRoot),
                directory: project.directory,
                running: runningAgents(of: member, in: project),
                openSubagent: { session, subagent in
                    selection = Tag.subagent(session, subagent)
                }
            )
            .id(member.id)
        } else if let block = selectedBlock(in: project), block.isDemo {
            DesignDemo(
                block: block, cards: project.cards,
                waiting: waitingSession(for: block, in: project),
                approve: { revision in approveDemo(block, revision: revision, in: project) },
                revise: { openDesigner(block, in: project) }
            )
            .id(block.id)
        } else if let block = selectedBlock(in: project) {
            BlockDetail(
                block: block, cards: project.cards,
                waiting: waitingSession(for: block, in: project),
                start: { startUnblock(block, in: project) },
                revise: { openProposal(block, approve: false, in: project) },
                resolve: { Blocks.resolve(block); reload() }
            )
            .id(block.id)
        } else if let task = reviewedTask(in: project) {
            TaskReview(task: task, summary: ChangeSummary.of(project, changes: changes),
                       directory: project.directory, cards: project.cards, team: project.team,
                       branch: branch, head: head, draft: draft(for: task.id),
                       openFile: { selection = Tag.review(project) + ":" + $0 },
                       approve: { approve(task, message: $0, in: project) },
                       requestChanges: { requestChanges(on: task, in: project) })
                .id(task.id)
        } else if let path = reviewPath(project) {
            let summary = ChangeSummary.of(project, changes: changes)
            // A file a task's worker claimed is reviewed as part of that task: comments on
            // its lines join that task's feedback, and the bar is that task's decision.
            let owner = path.isEmpty ? nil : summary.tasks.first { $0.files.contains { $0.path == path } }
            ChangeReview(project: project, changes: changes, head: head, branch: branch,
                         path: path, summary: summary,
                         select: { selection = Tag.review(project) + ":" + $0 },
                         commit: { commit($0, in: project) },
                         task: owner, draft: draft(for: owner?.id ?? ""),
                         openTask: { selection = Tag.reviewTask(project, $0) },
                         approve: { message in owner.flatMap { approve($0, message: message, in: project) } },
                         requestChanges: { if let owner { requestChanges(on: owner, in: project) } })
        } else if let step = previewStep(in: project) {
            ProjectPreview(repo: step.repo, services: step.services,
                           run: { runServices([step], in: project) })
                .id(selection)
        } else if let entry = selectedEntry {
            NotebookEditor(entry: entry).id(entry.id)
        } else if selectedSession(in: project) != nil {
            // The terminal itself is mounted underneath; this pane stays out of its way.
            Color.clear
        } else {
            VStack(spacing: 8) {
                Image(systemName: section.systemImage).font(.system(size: 22))
                    .foregroundStyle(Theme.tx4)
                Text("Nothing selected in \(section.title).")
                    .font(Typo.text(13)).foregroundStyle(Theme.tx3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        }
    }

    private func boardView(for project: Project) -> some View {
        NotebookBoard(
            cards: project.cards,
            blocks: project.blocks,
            assigned: project.assignedTaskIDs,
            showDone: showDone,
            assign: { tasks in assign(tasks, in: project) },
            review: { startProductReview(in: project) },
            openCard: { card in selection = Tag.task(card.id) },
            openDemo: { demo in selection = Tag.block(demo) },
            remove: { card in remove(card, in: project) }
        )
    }

    /// Approving a demo is the one gesture that releases the engineering tasks waiting on
    /// a design task: the block is cleared the same way any other is, and the agent that
    /// made it is told which revision won. The app does not touch the task file — the
    /// agent owns that, like every other status in the notebook.
    private func approveDemo(_ block: UserBlock, revision: DemoRevision?, in project: Project) {
        Blocks.resolve(block)
        if let waiting = waitingSession(for: block, in: project) {
            let pass = revision.map { " Build \($0.label)." } ?? ""
            pendingInput[waiting.id] = "The demo at \(block.slug) is approved.\(pass) "
                + "Mark the design task done and start the tasks waiting on it."
            section = .agents
            selection = Tag.session(waiting)
        }
        reload()
    }

    /// Saying what is wrong goes to whoever made the demo, in their own transcript. There
    /// is nothing to type on their behalf — the point is that the user says it.
    private func openDesigner(_ block: UserBlock, in project: Project) {
        guard let waiting = waitingSession(for: block, in: project) else { return }
        section = .agents
        selection = Tag.session(waiting)
    }

    // MARK: - Selection

    private func openSectionDefault() {
        guard let project = enteredProject else { return }
        switch section {
        case .overview:
            selection = Tag.overview(project)
        case .board:
            if Tag.card(selection, in: project.cards) == nil {
                selection = Tag.board(project)
            }
        case .agents:
            if selectedAgent(in: project) == nil && selectedSubagent(in: project) == nil
                && selectedSession(in: project) == nil && selectedMember(in: project) == nil
                && selection != Tag.usage(project) {
                // A lead first, then any agent — and a service runner only if that is all
                // there is, on its own tag, because it has no transcript to open.
                selection = (project.sessions.first { $0.isEngineeringLead }
                             ?? project.sessions.first { $0.agent != nil })
                    .map { Tag.session($0) }
                    ?? project.sessions.first.map { Tag.session($0) }
            }
        case .review:
            refreshChanges(force: true)
            // A task, not a file: what the agents did is the thing to read before any of
            // the diff means anything.
            selection = firstReview(in: project)
        case .blocks:
            selection = (project.blocks.first(where: \.waiting)
                         ?? (showDone ? project.blocks.first : nil))
                .map { Tag.block($0) }
        }
    }

    private func isVisible(_ session: CodeSession) -> Bool {
        enteredProject.map { project in
            selection == Tag.session(session) || selectedSubagent(in: project)?.session.id == session.id
        } ?? false
    }

    private func selectedSession(in project: Project) -> CodeSession? {
        project.sessions.first { Tag.session($0) == selection }
    }

    /// The team member the selection is on. A member is a file, not a session, so it is
    /// matched by roster name — the tag survives the reload the same way.
    private func selectedMember(in project: Project) -> TeamMember? {
        Tag.scope(selection, "member").flatMap { name in project.team.first { $0.name == name } }
    }

    /// The agents running this member's skill right now, wherever they were dispatched
    /// from — the way back from a standing agent into the work it is doing.
    private func runningAgents(of member: TeamMember,
                               in project: Project) -> [(session: CodeSession, subagent: SubagentStatus)] {
        project.sessions.flatMap { session in
            session.activeSubagents.filter { $0.member == member.name }
                .map { (session: session, subagent: $0) }
        }
    }

    /// The agent session the selection is on, whichever of its panes is showing — its
    /// terminal included, so switching to the session does not take the pane switch away
    /// with it. A service terminal is not an agent and has no transcript to watch.
    private func selectedAgent(in project: Project) -> CodeSession? {
        project.sessions.first {
            $0.agent != nil && AgentPane.of(selection, session: $0.id) != nil
        }
    }

    private func agentPane(_ session: CodeSession) -> Binding<AgentPane> {
        Binding(
            get: { AgentPane.of(selection, session: session.id) ?? .session },
            set: {
                selection = $0.tag(session.id)
                reloadAgentTranscript()
            }
        )
    }

    /// A project with no notebook and no agent yet — the one case that starts a chat.
    private var needsIntake: Project? {
        enteredProject.flatMap { $0.hasNotebook || !$0.sessions.isEmpty ? nil : $0 }
    }

    private var selectedEntry: NotebookEntry? {
        guard let selection, let project = enteredProject else { return nil }
        return NotebookLoader.find(selection, in: project.entries)
    }

    private func scopedCard(in project: Project, kind: EntryKind) -> NotebookCard? {
        guard let id = Tag.scope(selection, kind == .project ? "project" : "task") else { return nil }
        return project.cards.first { $0.id == id && $0.kind == kind }
    }

    private func scopedPageCard(in project: Project) -> NotebookCard? {
        guard let id = Tag.scope(selection, "page") else { return nil }
        return project.cards.first { $0.id == id }
    }

    /// Every subagent in this project that was dispatched for one task, whichever lead
    /// spawned it. The link is the subagent's own name, matched when it is read off disk.
    private func workers(on taskID: String, in project: Project) -> [(CodeSession, SubagentStatus)] {
        project.sessions.flatMap { session in
            session.subagents.filter { $0.taskID == taskID }.map { (session, $0) }
        }
    }

    private func selectedSubagent(in project: Project) -> (session: CodeSession, subagent: SubagentStatus)? {
        guard let selection else { return nil }
        for session in project.sessions {
            if let subagent = session.subagents.first(where: { Tag.subagent(session, $0) == selection }) {
                return (session, subagent)
            }
        }
        return nil
    }

    private func selectedBlock(in project: Project) -> UserBlock? {
        project.blocks.first { Tag.block($0) == selection }
    }

    /// The file a review selection points at, or "" for the review screen with nothing
    /// picked yet. Nil when the selection is not a review at all.
    private func reviewPath(_ project: Project) -> String? {
        let root = Tag.review(project)
        guard let selection, selection.hasPrefix(root) else { return nil }
        let rest = selection.dropFirst(root.count)
        return rest.hasPrefix(":") ? String(rest.dropFirst()) : ""
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
    private func assign(_ tasks: [NotebookCard], in project: Project) {
        let batch = NotebookIndex.withBlockers(tasks, in: project.cards, excluding: project.assignedTaskIDs)
        guard !batch.isEmpty else {
            guard !tasks.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "Nothing to assign"
            alert.informativeText = "Every task here is already done, or already has an Engineering "
                + "Lead on it — wait for that session to finish, or close it, before assigning again."
            alert.runModal()
            return
        }
        section = .agents
        if let lead = project.sessions.first(where: { $0.isEngineeringLead && !$0.exited }) {
            let leadAgent = lead.agent ?? .claude
            appendTaskIDs(batch.map(\.id), to: lead, in: project)
            pendingInput[lead.id] = NotebookFormat.additionalTasksPrompt(tasks: batch, sessionID: lead.id,
                                                                         agent: leadAgent)
            selection = Tag.session(lead)
            return
        }
        // The id is minted here so the prompt can carry it: a lead that knows its own
        // session id can write it into any block it raises, and the answer comes back here.
        let id = UUID()
        addSession(agent, id: id, to: project,
                   prompt: NotebookFormat.engineeringPrompt(tasks: batch, sessionID: id, agent: agent),
                   title: "Engineering Lead", taskIDs: batch.map(\.id))
    }

    private func addMenu(for project: Project) -> some View {
        Menu {
            Section("Session") {
                Button(agent.displayName, systemImage: agent.systemImage) {
                    addSession(agent, to: project)
                    section = .agents
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

    /// The session this block is holding up. A block names its own session, so the answer
    /// reaches the lead that asked even with several running; one written without a
    /// session id falls back to the newest live lead, which is the single-lead case.
    private func waitingSession(for block: UserBlock, in project: Project) -> CodeSession? {
        // A proposal links to Product, but does not block an engineering session.
        guard !block.isProposal else { return nil }
        if let id = block.session {
            return project.sessions.first { $0.id == id && !$0.exited }
        }
        return project.sessions.last { $0.isEngineeringLead && !$0.exited }
    }

    /// A gate starts a session whose only job is unblocking it. A proposal instead returns
    /// to its Product transcript, and only a ready proposal's create button sends approval.
    ///
    /// The page is deliberately not opened here. A browser tab that appears before the
    /// session has said anything lands the user on a token screen with no idea what it is
    /// for; the engineer explains first, and opens the page when the user is ready for it.
    private func startUnblock(_ block: UserBlock, in project: Project) {
        guard !block.isProposal else {
            return openProposal(block, approve: block.proposalReady, in: project)
        }
        addSession(agent, to: project, prompt: NotebookFormat.unblockPrompt(block: block, agent: agent),
                   title: "Unblock \(block.title)")
        section = .agents
    }

    /// A proposal belongs to the Product conversation that shaped it. Opening it is only
    /// navigation; the ready proposal's explicit create action is the approval message.
    private func openProposal(_ block: UserBlock, approve: Bool, in project: Project) {
        let running = block.session.flatMap { id in
            project.sessions.first { $0.id == id && !$0.exited }
        } ?? project.sessions.last { isProduct($0) && !$0.exited }
        if let running {
            section = .agents
            selection = Tag.session(running)
            if approve {
                pendingInput[running.id] = "Approved. Create the roadmap changes, project, and tasks in this ready proposal."
            }
            return
        }
        let decision = approve ? "\nDecision: approve" : ""
        startProduct(NotebookFormat.relativePath(block.url) + decision, in: project)
    }

    /// A block whose file has flipped to done is news the waiting session cannot see —
    /// it is sitting at a prompt. Typing it in is what closes the loop the user opened by
    /// pressing the button.
    private func deliverUnblocks(in project: Project) {
        for block in project.blocks where !block.waiting && !deliveredBlocks.contains(block.id) {
            guard let session = waitingSession(for: block, in: project) else { continue }
            deliveredBlocks.insert(block.id)
            pendingInput[session.id] = NotebookFormat.unblockedMessage(block: block)
            section = .agents
            selection = session.id.uuidString
        }
    }

    // MARK: - Projects

    private func openProject() {
        guard let path = pickDirectory(
            message: "Agents run in this folder and its notebook lives in \(NotebookFormat.folderName)/."
        ) else { return }
        let directory = URL(fileURLWithPath: path)
        if let existing = projects.first(where: { $0.directory.path == directory.path }) {
            enter(existing)
            return
        }
        let project = Project(directory: directory,
                              entries: NotebookLoader.load(root: NotebookFormat.root(in: directory)))
        projects.append(project)
        persist()
        enter(project)
    }

    /// Where a described project lands when its prompt names nowhere: beside the ones
    /// already open, since that is where this person keeps projects, and `~/Projects` on
    /// a first run. Created on the way, so nothing has to be picked in a panel first.
    private var projectsParent: URL {
        projects.last.map { $0.directory.deletingLastPathComponent() }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects")
    }

    /// A project described rather than opened: the folder is new and empty, so the prompt
    /// that named it goes straight to the session that writes its notebook — the intake
    /// screen has nothing left to ask.
    private func createProject(at directory: URL, prompt: String) {
        creatingProject = false
        if let existing = projects.first(where: { $0.directory.path == directory.path }) {
            enter(existing)
            return
        }
        let project = Project(directory: directory,
                              entries: NotebookLoader.load(root: NotebookFormat.root(in: directory)))
        projects.append(project)
        persist()
        enter(project)
        guard let started = enteredProject, !started.hasNotebook else { return }
        section = .agents
        addSession(agent, to: started,
                   prompt: NotebookFormat.onboardingPrompt(description: prompt),
                   title: "Notebook Setup")
    }

    /// Reopens last session's folders, dropping any that have since been moved away.
    private func restore() {
        guard projects.isEmpty else { return }
        if CommandLine.arguments.contains("--attention-selftest") {
            runAttentionSelfTest()
            return
        }
        projects = OpenProjects.decode(openProjects)
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { path in
                let directory = URL(fileURLWithPath: path)
                return Project(directory: directory,
                               entries: NotebookLoader.load(root: NotebookFormat.root(in: directory)))
            }
        persist()
        reload()
    }

    /// Full app regression: actual Codex screen bytes travel through the PTY,
    /// representable callback, app state, banner and session navigation. No real agent.
    private func runAttentionSelfTest() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yk-attention-\(UUID())")
        let root = NotebookFormat.root(in: directory)
        _ = try! NotebookFormat.create(.task, title: "Trust screen test", in: root, project: nil)
        let output = directory.appendingPathComponent("trust.ansi")
        try! NotebookSelfTest.codexTrustScreen.write(to: output, atomically: true, encoding: .utf8)
        var project = Project(directory: directory, entries: NotebookLoader.load(root: root))
        let session = CodeSession(title: "Engineering Lead", icon: "terminal",
                                  line: "cat \(AgentCommand.quoted(output.path)); exec sleep 30", agent: .codex)
        project.sessions = [session]
        projects = [project]
        entered = project.id
        section = .agents
        selection = Tag.session(session)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            precondition(attention[session.id] != nil, "PTY callback must reach the app's banner state")
            guard let host = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                  let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                preconditionFailure("attention selftest needs a rendered app window")
            }
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "/tmp/yongkang-attention-selftest.png"))
            openAttention(session, in: project)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                precondition(isVisible(session), "Open session must reveal the blocked terminal")
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
        openProjects = OpenProjects.encode(projects.map(\.directory.path))
    }

    private func enter(_ project: Project) {
        entered = project.id
        doneTasks = nil
        section = .overview
        selection = Tag.overview(project)
        reload()
        refreshChanges(force: true)
        // The lead is started by an assignment, not by opening the project — an empty
        // project opens on Overview. One already running from an earlier batch is still
        // live, standing by, so the project opens on it.
        guard let ready = enteredProject, ready.hasNotebook else { return }
        Team.seedIfAbsent(root: ready.notebookRoot)
        guard ready.sessions.contains(where: { $0.isEngineeringLead && !$0.exited }) else { return }
        section = .agents
        openSectionDefault()
    }

    private func leave() {
        entered = nil
        doneTasks = nil
        selection = nil
        reload()
    }

    private func close(_ project: Project) {
        for session in project.sessions { attentionChanged(nil, session: session, project: project) }
        projects.removeAll { $0.id == project.id }
        persist()
        if entered == project.id { leave() }
    }

    /// Product looks at the whole product and discusses what should come next. Blocks gets
    /// one link back to that transcript, then the finalized plan; the board stays unchanged
    /// until the user explicitly creates it.
    private func startProductReview(in project: Project) {
        startProduct("review", in: project)
    }

    /// One product voice per project. A second session would propose against a board the
    /// first one is already rewriting, so a running one is talked to instead — the same
    /// rule the Engineering Lead follows for a second batch.
    private func startProduct(_ arguments: String, in project: Project) {
        section = .agents
        if let running = project.sessions.first(where: { isProduct($0) && !$0.exited }) {
            let productAgent = running.agent ?? .claude
            pendingInput[running.id] = NotebookFormat.productPrompt(
                arguments: arguments, sessionID: running.id, agent: productAgent
            )
            selection = Tag.session(running)
            return
        }
        let id = UUID()
        addSession(agent, id: id, to: project,
                   prompt: NotebookFormat.productPrompt(arguments: arguments, sessionID: id, agent: agent),
                   title: "Product")
    }

    /// Incubate mode: the app does not write the agent, a session does. It searches the
    /// skills this project can already load, fetches or writes what is missing, and adds
    /// the file to `.notebook/team/` — which the poll picks up as a new roster row, the
    /// same way any other notebook entry an agent writes turns up.
    private func startIncubation(_ brief: String, in project: Project) {
        section = .agents
        addSession(agent, to: project,
                   prompt: NotebookFormat.incubatePrompt(brief: brief, agent: agent),
                   title: "New Agent")
    }

    private func isProduct(_ session: CodeSession) -> Bool {
        session.title == "Product" || session.title.hasPrefix("Product ")
    }

    /// One row per repo actually on disk, deduped across every notebook project.
    private func previewRows(for project: Project)
        -> [(id: String, repo: String, directory: URL, services: [Service.Runnable])] {
        let steps = project.cards.filter { $0.kind == .project }
            .flatMap { Service.plan(for: $0, in: project.directory) }
        return Service.dedupedByDirectory(steps).map { step in
            (id: Tag.preview(project, step.directory), repo: step.repo,
             directory: step.directory, services: step.services)
        }
    }

    /// The repo a preview tag points at, or nil if `selection` is not one.
    private func previewStep(in project: Project)
        -> (repo: String, directory: URL, services: [Service.Runnable])? {
        guard let selection else { return nil }
        guard let row = previewRows(for: project).first(where: { $0.id == selection }) else { return nil }
        return (row.repo, row.directory, row.services)
    }

    // MARK: - Reloading

    private func reload() {
        ticks += 1
        for index in projects.indices {
            let entries = NotebookLoader.load(root: projects[index].notebookRoot)
            if entries != projects[index].entries { projects[index].entries = entries }
            // The project you are inside pays for reading frontmatter and transcripts; on
            // the fleet screen every project does, because that screen is what it costs.
            guard projects[index].id == entered || entered == nil
                    || projects[index].sessions.contains(where: { $0.agent != nil && !$0.exited }) else { continue }
            let cards = NotebookIndex.load(root: projects[index].notebookRoot)
            if cards != projects[index].cards { projects[index].cards = cards }
            let blocks = Blocks.load(root: projects[index].notebookRoot)
            if blocks != projects[index].blocks { projects[index].blocks = blocks }
            let team = Team.load(root: projects[index].notebookRoot)
            if team != projects[index].team { projects[index].team = team }
            if projects[index].id == entered {
                let records = LeadCoordination.all(root: projects[index].notebookRoot)
                if records != projects[index].records { projects[index].records = records }
            }
            if projects[index].id == entered {
                showFinishedWork(in: projects[index])
                deliverUnblocks(in: projects[index])
            }
            for sIndex in projects[index].sessions.indices
                where projects[index].sessions[sIndex].agent != nil {
                let session = projects[index].sessions[sIndex]
                if !session.exited {
                    let subagents = subagents(of: session, in: projects[index])
                    if subagents != session.subagents { projects[index].sessions[sIndex].subagents = subagents }
                }
                guard !session.taskIDs.isEmpty else { continue }
                let coordination = LeadCoordination.load(root: projects[index].notebookRoot,
                                                         session: projects[index].sessions[sIndex])
                if coordination != session.coordination {
                    projects[index].sessions[sIndex].coordination = coordination
                }
            }
            // Written from the poll rather than from the usage screen: what an agent spent
            // has to survive a run in which nobody opened that screen, and the transcripts
            // it is read from are no longer findable once the sessions are gone.
            UsageLedger.record(AgentUsage.spends(in: projects[index]),
                               root: projects[index].notebookRoot)
        }
        reloadAgentTranscript()
        refreshChanges()
    }

    /// A task turning done is the moment to read what changed, so the window opens the
    /// review itself rather than waiting to be asked — the summary, its diff and the
    /// commit line, which is everything the handover needs.
    ///
    /// Not while a terminal is up: that pane has the keyboard, and pulling it away would
    /// drop the user's next keystrokes into an agent they can no longer see.
    private func showFinishedWork(in project: Project) {
        let done = Set(project.cards.filter { $0.kind == .task && $0.status == "done" }.map(\.id))
        let seen = doneTasks
        if doneTasks != done { doneTasks = done }
        guard let seen, !done.subtracting(seen).isEmpty,
              selectedSession(in: project) == nil else { return }
        section = .review
        refreshChanges(force: true)
        selection = firstReview(in: project)
    }

    /// The task page to land on: the first one waiting for approval, or the whole working
    /// tree when nothing is.
    private func firstReview(in project: Project) -> String {
        ChangeSummary.of(project, changes: changes).waiting.first
            .map { Tag.reviewTask(project, $0.id) } ?? Tag.review(project)
    }

    private func reviewedTask(in project: Project) -> SummaryTask? {
        let prefix = "review-task:\(project.id.uuidString):"
        guard let selection, selection.hasPrefix(prefix) else { return nil }
        let id = String(selection.dropFirst(prefix.count))
        return ChangeSummary.of(project, changes: changes).tasks.first { $0.id == id }
    }

    private func draft(for taskID: String) -> Binding<ReviewDraft> {
        Binding(get: { reviewDrafts[taskID] ?? ReviewDraft() },
                set: { reviewDrafts[taskID] = $0 == ReviewDraft() ? nil : $0 })
    }

    /// Approving is committing: only this task's files and its records, then on to the
    /// next task waiting. Nothing is sent to the lead — it already marked the task done.
    private func approve(_ task: SummaryTask, message: String, in project: Project) -> String? {
        let failure = GitChanges.commit(message: message, paths: task.commitPaths, in: project.directory)
        refreshChanges(force: true)
        guard failure == nil else { return failure }
        reviewDrafts[task.id] = nil
        selection = firstReview(in: project)
        return nil
    }

    /// Sending a task back goes to the lead that holds it, typed into its terminal like any
    /// follow-up; with no lead running, a fresh one starts with the task and the comments.
    private func requestChanges(on task: SummaryTask, in project: Project) {
        guard let draft = reviewDrafts[task.id], !draft.isEmpty else { return }
        let message = draft.message(taskID: task.id, title: task.title)
        let leads = project.sessions.filter { $0.isEngineeringLead && !$0.exited }
        if let lead = leads.first(where: { $0.taskIDs.contains(task.id) }) ?? leads.first {
            if !lead.taskIDs.contains(task.id) { appendTaskIDs([task.id], to: lead, in: project) }
            reviewDrafts[task.id] = nil
            section = .agents
            pendingInput[lead.id] = message
            selection = Tag.session(lead)
            return
        }
        guard let card = project.cards.first(where: { $0.id == task.id }) else { return }
        reviewDrafts[task.id] = nil
        section = .agents
        let id = UUID()
        addSession(agent, id: id, to: project,
                   prompt: NotebookFormat.changeRequestPrompt(task: card, message: message, sessionID: id, agent: agent),
                   title: "Engineering Lead", taskIDs: [task.id])
    }

    /// git is only asked while a screen that shows its answer is open, and then only every
    /// third tick — a repo-wide diff twice a second is a cost with no reader.
    private func refreshChanges(force: Bool = false) {
        // Every section, not only Review: the rail's light says work is waiting for approval,
        // and it has to come on while you are looking at the board.
        guard let project = enteredProject else { return }
        guard force || ticks % 3 == 0 else { return }
        // A project the agents work in needs a repository: without one there is no diff to
        // review and nowhere for an approval to commit. Created, never committed to.
        if project.hasNotebook && !GitChanges.isRepository(project.directory) {
            _ = GitChanges.initialize(in: project.directory)
        }
        let fresh = GitChanges.changes(in: project.directory)
        if fresh != changes { changes = fresh }
        head = GitChanges.head(in: project.directory)
        branch = GitChanges.branch(in: project.directory)
    }

    /// The review screen's one write to the repo. Staging and committing is all it does —
    /// no push, no merge, no branch — and only because the user pressed the button.
    private func commit(_ message: String, in project: Project) -> String? {
        let failure = GitChanges.commit(message: message, in: project.directory)
        if failure == nil { selection = Tag.review(project) }
        refreshChanges(force: true)
        return failure
    }

    /// Each provider writes its subagents somewhere else — Claude Code beside the parent
    /// session, Codex as sibling rollouts pointing back at it — so the session's own agent
    /// picks the reader. A service terminal has neither and is skipped by the caller.
    private func subagents(of session: CodeSession, in project: Project) -> [SubagentStatus] {
        let found: [SubagentStatus]
        switch session.agent {
        case .codex:
            found = CodexTranscripts.subagents(sessionID: session.id, projectDirectory: project.directory,
                                               taskIDs: session.taskIDs)
        case .claude:
            found = ClaudeTranscripts.subagents(sessionID: session.id, projectDirectory: project.directory,
                                                taskIDs: session.taskIDs)
        default:
            found = []
        }
        // Named here rather than in either reader: the roster is project state, and the
        // screens downstream should never each have to look a running agent up themselves.
        return found.map { $0.named(in: project.team) }
    }

    /// Only the agent actually on screen pays for having its transcript read and parsed —
    /// everything else is covered by the status list above.
    private func reloadAgentTranscript() {
        guard let project = enteredProject, let source = onScreenTranscript(in: project) else {
            transcriptSource = nil
            agentTranscript = []
            return
        }
        let fresh: [TranscriptLine]
        switch source.agent {
        case .codex: fresh = CodexTranscripts.transcript(at: source.url)
        case .claude: fresh = ClaudeTranscripts.transcript(at: source.url)
        case .grok: fresh = GrokTranscripts.transcript(at: source.url)
        default: fresh = []
        }
        guard source.url != transcriptSource || fresh.count != agentTranscript.count else { return }
        transcriptSource = source.url
        agentTranscript = fresh
    }

    /// The transcript the work area is showing, if it is showing one: a subagent's, or the
    /// lead's own when its transcript pane is up.
    private func onScreenTranscript(in project: Project) -> (agent: AgentKind, url: URL)? {
        guard let watched = selectedAgent(in: project),
              AgentPane.of(selection, session: watched.id) == .transcript,
              let url = Transcripts.url(of: watched, in: project.directory) else { return nil }
        return (watched.agent ?? .claude, url)
    }

    // MARK: - Sessions

    /// `id` is generated up front so the same id names both the CLI's `--session-id` and
    /// this session's own row — that is what lets its transcript be found again later, and
    /// what a caller passes in when the prompt itself has to name the session.
    private func addSession(_ agent: AgentKind, id: UUID = UUID(), to project: Project,
                            prompt: String? = nil, title: String? = nil, taskIDs: [String] = []) {
        addSession(id: id, to: project, title: title ?? agent.displayName, icon: agent.systemImage,
                   line: AgentCommand.line(directory: project.directory.path,
                                           agent: agent, prompt: prompt, sessionID: id,
                                           brief: title?.hasPrefix("Engineering Lead") == true,
                                           noCommit: title?.hasPrefix("Engineering Lead") == true),
                   agent: agent, taskIDs: taskIDs)
    }

    private func addSession(id: UUID = UUID(), to project: Project, title: String, icon: String, line: String,
                            agent: AgentKind? = nil, taskIDs: [String] = []) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        // Second "Engineering Lead" becomes "Engineering Lead 2" — identical rows are
        // unusable, and several leads at once is a normal thing to want.
        let taken = projects[index].sessions.filter { $0.title == title || $0.title.hasPrefix(title + " ") }.count
        let name = taken == 0 ? title : "\(title) \(taken + 1)"
        projects[index].sessions.append(CodeSession(id: id, title: name, icon: icon, line: line,
                                                    agent: agent, taskIDs: taskIDs))
        // New sessions open their live CLI.
        selection = id.uuidString
    }

    /// Every service in a project's repos, started at once — the board's "run the whole
    /// project" action.
    private func runServices(_ card: NotebookCard, in project: Project) {
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
    private func runServices(_ steps: [(repo: String, directory: URL, services: [Service.Runnable])],
                             in project: Project) {
        let named = steps.flatMap { step in
            step.services.map { service in
                (label: service.name == step.repo ? step.repo : "\(step.repo)/\(service.name)",
                 directory: service.directory, command: service.command)
            }
        }
        section = .agents
        for service in named where service.command != nil {
            let title = "Run \(service.label)"
            if let running = project.sessions.first(where: { $0.title == title }) {
                selection = running.id.uuidString
                continue
            }
            addSession(to: project, title: title, icon: "play.circle",
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

    private func close(_ session: CodeSession, in project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        attentionChanged(nil, session: session, project: project)
        projects[index].sessions.removeAll { $0.id == session.id }
        if AgentPane.of(selection, session: session.id) != nil
            || selection?.hasPrefix("subagent:\(session.id.uuidString):") == true {
            selection = nil
        }
    }

    /// A computed binding into `pendingInput`, keyed by session — AgentTerminal clears it
    /// once it has typed the text in.
    private func pendingBinding(_ session: CodeSession) -> Binding<String?> {
        Binding(get: { pendingInput[session.id] }, set: { pendingInput[session.id] = $0 })
    }

    private func markExited(_ session: CodeSession, in project: Project) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }),
              let sIndex = projects[pIndex].sessions.firstIndex(where: { $0.id == session.id }) else { return }
        projects[pIndex].sessions[sIndex].exited = true
        attentionChanged(nil, session: session, project: project)
    }

    private func appendTaskIDs(_ ids: [String], to session: CodeSession, in project: Project) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }),
              let sIndex = projects[pIndex].sessions.firstIndex(where: { $0.id == session.id }) else { return }
        projects[pIndex].sessions[sIndex].taskIDs += ids
    }

    // MARK: - Notebook entries

    /// The `.notebook/projects/<id>` the selection sits in — memory has to land in one.
    private func notebookProject(in project: Project) -> String? {
        if let scope = Tag.scope(selection, "project") { return scope }
        if let id = Tag.scope(selection, "task"),
           let owner = project.cards.first(where: { $0.id == id })?.project { return owner }
        guard let selection,
              selection.hasPrefix(NotebookEntry.id(for: project.directory)),
              let marker = selection.range(of: "/\(NotebookFormat.folderName)/projects/")
        else { return nil }
        return selection[marker.upperBound...].split(separator: "/").first.map(String.init)
    }

    private func add(_ kind: EntryKind, to project: Project) {
        guard let title = askTitle(kind) else { return }
        do {
            let file = try NotebookFormat.create(kind, title: title, in: project.notebookRoot,
                                                 project: notebookProject(in: project),
                                                 roadmap: notebookRoadmap(in: project),
                                                 subject: notebookSubject(in: project))
            reload()
            let id = kind == .project ? file.deletingLastPathComponent().lastPathComponent
                                      : file.deletingPathExtension().lastPathComponent
            section = .board
            switch kind {
            case .project: selection = Tag.project(id)
            case .task: selection = Tag.task(id)
            case .roadmap, .memory, .run: selection = Tag.page(id)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Removing a notebook entry. A project takes its tasks with it — a task filed under
    /// an id that no longer exists shows up nowhere and would never be worked.
    private func remove(_ card: NotebookCard, in project: Project) {
        let tasks = NotebookFormat.owned(by: card, in: project.cards).count - 1
        let alert = NSAlert()
        alert.messageText = "Move \u{201C}\(card.title)\u{201D} to the Trash?"
        alert.informativeText = card.kind == .project
            ? "The project folder, its memory and its \(tasks) task\(tasks == 1 ? "" : "s") go with it. "
                + "You can put them back from the Trash."
            : "You can put it back from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try NotebookFormat.remove(card, in: project.cards)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        // Anything on screen that was inside what just went to the Trash has no page left.
        let gone = Set(NotebookFormat.owned(by: card, in: project.cards).map(\.path))
        if let shown = Tag.card(selection, in: project.cards),
           gone.contains(where: { shown.url.path == $0 || shown.url.path.hasPrefix($0 + "/") }) {
            selection = Tag.board(project)
        }
        reload()
    }

    private func notebookRoadmap(in project: Project) -> String? {
        if let id = Tag.scope(selection, "page"),
           project.cards.contains(where: { $0.id == id && $0.kind == .roadmap }) {
            return id
        }
        let roadmaps = project.cards.filter { $0.kind == .roadmap }
        return roadmaps.count == 1 ? roadmaps[0].id : nil
    }

    private func notebookSubject(in project: Project) -> String? {
        if let id = Tag.scope(selection, "task") ?? Tag.scope(selection, "project")
            ?? Tag.scope(selection, "page") { return id }
        return notebookProject(in: project)
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


extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
