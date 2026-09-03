import SwiftUI
import AppKit
import Combine

@main
struct ClaudeCodeApp: App {
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
    /// Text queued to be typed into a running session, keyed by session id — how a task
    /// reaches a lead that already exists instead of starting a competing one.
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
    @State private var head: String?
    @State private var branch: String?
    @State private var ticks = 0
    /// Completed notebook work is historical noise until the user asks for it.
    @State private var showDone = false
    /// Blocks already reported back to the session that was waiting, so a cleared block
    /// says so once rather than on every 2-second poll.
    @State private var deliveredBlocks: Set<String> = []
    /// Which folders were open last time. Sessions are not restored — the agents died
    /// with the app — but the projects and their notebooks come back.
    @AppStorage("openProjects") private var openProjects = "[]"
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
            .preferredColorScheme(.dark)
            .frame(minWidth: 1120, minHeight: 680)
            .task { restore() }
            .onReceive(tick) { _ in reload() }
            .onChange(of: section) { _ in openSectionDefault() }
        }
        .windowToolbarStyle(.unified)
    }

    private var enteredProject: Project? { projects.first { $0.id == entered } }

    // MARK: - Chrome

    private var terminals: some View {
        ForEach(projects) { project in
            ForEach(project.sessions) { session in
                AgentTerminal(line: session.line, label: session.title,
                              pending: pendingBinding(session),
                              onExit: { markExited(session, in: project) })
                    .padding(.leading, Theme.railWidth + Theme.listWidth)
                    .padding(.top, Theme.topBarHeight)
                    .opacity(isVisible(session) ? 1 : 0)
                    .allowsHitTesting(isVisible(session))
                    .accessibilityHidden(!isVisible(session))
            }
        }
    }

    @ViewBuilder private var chrome: some View {
        if entered == nil {
            ProjectsHome(projects: projects, agent: $agent, enter: enter,
                         add: openProject, close: close)
        } else if let project = enteredProject {
            HStack(spacing: 0) {
                Rail(section: $section, badges: badges(for: project), leave: leave)
                ProjectList(section: section, project: project, selection: $selection,
                            showDone: showDone, changes: changes,
                            assign: { assign($0, in: project) },
                            closeSession: { close($0, in: project) })
                VStack(spacing: 0) {
                    topBar(for: project)
                    screen(for: project)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// A dot on the rail for the two things that are about the user rather than the work:
    /// something waiting on them, and something an agent has left to be read.
    private func badges(for project: Project) -> [ConsoleSection: Color] {
        var badges: [ConsoleSection: Color] = [:]
        if project.blocks.contains(where: \.waiting) { badges[.blocks] = Theme.amber }
        if project.sessions.contains(where: { !$0.activeSubagents.isEmpty }) {
            badges[.agents] = Theme.accent
        }
        if !changes.isEmpty { badges[.review] = Theme.green }
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
            TopBar(crumbs: [project.name], title: scoped?.title ?? "Board") {
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
                   title: selectedSubagent(in: project)?.subagent.description
                        ?? watched?.title ?? "Agents") {
                if let watched, selectedSubagent(in: project) == nil {
                    let panes = AgentPane.cases(lead: watched.isEngineeringLead)
                    Picker("", selection: agentPane(watched)) {
                        ForEach(panes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .frame(width: panes.count == 3 ? 250 : 175)
                }
                if let found = selectedSubagent(in: project) {
                    Button { openLiveTerminal(found.subagent, in: found.session) } label: {
                        Label("Terminal", systemImage: "terminal")
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
        case .terminals:
            TopBar(crumbs: [project.name],
                   title: selectedSession(in: project)?.title ?? "Terminals") {
                addMenu(for: project)
            }
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
        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
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
                    reload()
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
                    openTask: { section = .board; selection = Tag.task($0) },
                    openSubagent: { subagent in
                        selection = Tag.subagent(watched, subagent)
                        reload()
                    },
                    openBlock: { section = .blocks; selection = Tag.block($0) }
                )
            case .session:
                // The session's terminal is mounted underneath; this pane stays out of its way.
                Color.clear
            default:
                SessionTranscript(
                    session: watched, cards: project.cards, blocks: project.blocks,
                    lines: agentTranscript,
                    source: sessionTranscript(of: watched, in: project.directory),
                    openTask: { section = .board; selection = Tag.task($0) },
                    openBlock: { section = .blocks; selection = Tag.block($0) },
                    openSubagent: { subagent in
                        selection = Tag.subagent(watched, subagent)
                        reload()
                    }
                )
            }
        } else if let found = selectedSubagent(in: project) {
            SubagentViewer(session: found.session, subagent: found.subagent,
                           lines: agentTranscript,
                           task: found.subagent.taskID.flatMap { id in
                               project.cards.first { $0.id == id }
                           },
                           openTask: { section = .board; selection = Tag.task($0) })
                .id(selection)
        } else if let block = selectedBlock(in: project) {
            BlockDetail(
                block: block, cards: project.cards,
                waiting: waitingSession(for: block, in: project),
                start: { startUnblock(block, in: project) },
                resolve: { Blocks.resolve(block); reload() }
            )
            .id(block.id)
        } else if reviewPath(project) != nil {
            ChangeReview(project: project, changes: changes, head: head, branch: branch,
                         path: reviewPath(project) ?? "",
                         select: { selection = Tag.review(project) + ":" + $0 })
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
            assigned: project.assignedTaskIDs,
            showDone: showDone,
            assign: { tasks in assign(tasks, in: project) },
            review: { startProductReview(in: project) },
            openCard: { card in selection = Tag.task(card.id) }
        )
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
            if selectedAgent(in: project) == nil && selectedSubagent(in: project) == nil {
                selection = (project.sessions.first { $0.isEngineeringLead }
                             ?? project.sessions.first { $0.agent != nil })
                    .map { Tag.transcript($0.id) }
            }
        case .review:
            refreshChanges(force: true)
            selection = Tag.review(project) + ":" + (changes.first?.path ?? "")
        case .blocks:
            selection = (project.blocks.first(where: \.waiting) ?? project.blocks.first)
                .map { Tag.block($0) }
        case .terminals:
            if selectedSession(in: project) == nil {
                selection = project.sessions.first.map { Tag.session($0) }
            }
        }
    }

    private func isVisible(_ session: CodeSession) -> Bool {
        entered != nil && selection == session.id.uuidString
    }

    private func selectedSession(in project: Project) -> CodeSession? {
        project.sessions.first { Tag.session($0) == selection }
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
            get: { AgentPane.of(selection, session: session.id) ?? .transcript },
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

    /// Brings the lead's terminal forward and sends that CLI's own subagent picker:
    /// `/tasks` in Claude Code, `/agent` in Codex. Both are best-effort — exact with one
    /// subagent running, a list to pick from with several, since neither can be told which
    /// one to open.
    private func openLiveTerminal(_ subagent: SubagentStatus, in session: CodeSession) {
        section = .terminals
        selection = session.id.uuidString
        pendingInput[session.id] = session.agent == .codex ? "/agent" : "/tasks"
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
            selection = Tag.transcript(lead.id)
            return
        }
        // The id is minted here so the prompt can carry it: a lead that knows its own
        // session id can write it into any block it raises, and the answer comes back here.
        let id = UUID()
        addSession(agent, id: id, to: project,
                   prompt: NotebookFormat.engineeringPrompt(tasks: batch, sessionID: id, agent: agent),
                   title: "Engineering Lead", taskIDs: batch.map(\.id))
        selection = Tag.transcript(id)
    }

    private func addMenu(for project: Project) -> some View {
        Menu {
            Section("Session") {
                Button(agent.displayName, systemImage: agent.systemImage) {
                    addSession(agent, to: project)
                    section = .terminals
                }
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
        // Nothing sits blocked on a proposal — product raised it and went home.
        guard !block.isProposal else { return nil }
        if let id = block.session {
            return project.sessions.first { $0.id == id && !$0.exited }
        }
        return project.sessions.last { $0.isEngineeringLead && !$0.exited }
    }

    /// The button on a block starts a session whose only job is this one gate. It is a full
    /// session rather than a message to the lead because the lead is busy waiting — and
    /// because setup is a conversation (paste this, approve that) that should not be
    /// interleaved with the work it is blocking.
    ///
    /// The page is deliberately not opened here. A browser tab that appears before the
    /// session has said anything lands the user on a token screen with no idea what it is
    /// for; the engineer explains first, and opens the page when the user is ready for it.
    private func startUnblock(_ block: UserBlock, in project: Project) {
        guard !block.isProposal else {
            return startProduct(NotebookFormat.relativePath(block.url), in: project)
        }
        addSession(agent, to: project, prompt: NotebookFormat.unblockPrompt(block: block, agent: agent),
                   title: "Unblock \(block.title)")
        section = .terminals
    }

    /// A block whose file has flipped to done is news the waiting session cannot see —
    /// it is sitting at a prompt. Typing it in is what closes the loop the user opened by
    /// pressing the button.
    private func deliverUnblocks(in project: Project) {
        for block in project.blocks where !block.waiting && !deliveredBlocks.contains(block.id) {
            guard let session = waitingSession(for: block, in: project) else { continue }
            deliveredBlocks.insert(block.id)
            pendingInput[session.id] = NotebookFormat.unblockedMessage(block: block)
            section = .terminals
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

    /// Reopens last session's folders, dropping any that have since been moved away.
    private func restore() {
        guard projects.isEmpty else { return }
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

    private func persist() {
        openProjects = OpenProjects.encode(projects.map(\.directory.path))
    }

    private func enter(_ project: Project) {
        entered = project.id
        section = .overview
        selection = Tag.overview(project)
        reload()
        refreshChanges(force: true)
    }

    private func leave() {
        entered = nil
        selection = nil
        reload()
    }

    private func close(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        persist()
        if entered == project.id { leave() }
    }

    /// Product looks at the board and says what should come next. It writes proposals into
    /// `blocks/` rather than straight into the notebook, so nothing lands on the board
    /// without the user agreeing to it — the same folder, and the same button, as a gate.
    private func startProductReview(in project: Project) {
        startProduct("review", in: project)
    }

    /// One product voice per project. A second session would propose against a board the
    /// first one is already rewriting, so a running one is talked to instead — the same
    /// rule the Engineering Lead follows for a second batch.
    private func startProduct(_ arguments: String, in project: Project) {
        section = .terminals
        if let running = project.sessions.first(where: { $0.title == "Product" && !$0.exited }) {
            pendingInput[running.id] = (running.agent ?? .claude).skill("product", arguments: arguments)
            selection = running.id.uuidString
            return
        }
        addSession(agent, to: project, prompt: agent.skill("product", arguments: arguments), title: "Product")
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
            guard projects[index].id == entered || entered == nil else { continue }
            let cards = NotebookIndex.load(root: projects[index].notebookRoot)
            if cards != projects[index].cards { projects[index].cards = cards }
            let blocks = Blocks.load(root: projects[index].notebookRoot)
            if blocks != projects[index].blocks { projects[index].blocks = blocks }
            guard projects[index].id == entered else { continue }
            deliverUnblocks(in: projects[index])
            for sIndex in projects[index].sessions.indices
                where !projects[index].sessions[sIndex].exited
                    && projects[index].sessions[sIndex].agent != nil {
                let session = projects[index].sessions[sIndex]
                let subagents = subagents(of: session, in: projects[index].directory)
                if subagents != session.subagents { projects[index].sessions[sIndex].subagents = subagents }
            }
        }
        reloadAgentTranscript()
        refreshChanges()
    }

    /// git is only asked while a screen that shows its answer is open, and then only every
    /// third tick — a repo-wide diff twice a second is a cost with no reader.
    private func refreshChanges(force: Bool = false) {
        guard let project = enteredProject, section == .review || section == .overview else { return }
        guard force || ticks % 3 == 0 else { return }
        let fresh = GitChanges.changes(in: project.directory)
        if fresh != changes { changes = fresh }
        head = GitChanges.head(in: project.directory)
        branch = GitChanges.branch(in: project.directory)
    }

    /// Each provider writes its subagents somewhere else — Claude Code beside the parent
    /// session, Codex as sibling rollouts pointing back at it — so the session's own agent
    /// picks the reader. A service terminal has neither and is skipped by the caller.
    private func subagents(of session: CodeSession, in directory: URL) -> [SubagentStatus] {
        switch session.agent {
        case .codex:
            return CodexTranscripts.subagents(sessionID: session.id, projectDirectory: directory,
                                              taskIDs: session.taskIDs)
        default:
            return ClaudeTranscripts.subagents(sessionID: session.id, projectDirectory: directory,
                                               taskIDs: session.taskIDs)
        }
    }

    /// Only the agent actually on screen pays for having its transcript read and parsed —
    /// everything else is covered by the status list above.
    private func reloadAgentTranscript() {
        guard let project = enteredProject, let source = onScreenTranscript(in: project) else { return }
        let fresh = source.agent == .codex ? CodexTranscripts.transcript(at: source.url)
                                           : ClaudeTranscripts.transcript(at: source.url)
        guard source.url != transcriptSource || fresh.count != agentTranscript.count else { return }
        transcriptSource = source.url
        agentTranscript = fresh
    }

    /// The transcript the work area is showing, if it is showing one: a subagent's, or the
    /// lead's own when its transcript pane is up.
    private func onScreenTranscript(in project: Project) -> (agent: AgentKind, url: URL)? {
        if let found = selectedSubagent(in: project) {
            return (found.session.agent ?? .claude, found.subagent.transcriptURL)
        }
        guard let watched = selectedAgent(in: project),
              AgentPane.of(selection, session: watched.id) == .transcript,
              let url = sessionTranscript(of: watched, in: project.directory) else { return nil }
        return (watched.agent ?? .claude, url)
    }

    /// A session's own transcript — the parent half of what `subagents(of:in:)` reads for
    /// the agents it spawned, and found the same per-provider way. Nil for a Codex session
    /// whose opening prompt does not quote its id: there is nothing on disk to join on,
    /// which is why its subagents never resolve either.
    private func sessionTranscript(of session: CodeSession, in directory: URL) -> URL? {
        switch session.agent {
        case .codex:
            return CodexTranscripts.transcriptURL(sessionID: session.id, projectDirectory: directory)
        default:
            return ClaudeTranscripts.transcriptURL(sessionID: session.id, projectDirectory: directory)
        }
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
                                           brief: title?.hasPrefix("Engineering Lead") == true),
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
        selection = projects[index].sessions.last?.id.uuidString
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
        section = .terminals
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

private func pickDirectory(message: String) -> String? {
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
