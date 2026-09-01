import SwiftUI
import AppKit
import Combine

private enum EngineeringLeadPane: String, CaseIterable, Identifiable {
    case agents = "Agents"
    case session = "Session"

    var id: Self { self }
}

@main
struct ClaudeCodeApp: App {
    // ponytail: no folder is touched until the user picks one. Defaulting to $HOME made
    // claude scan the home folder and trip every TCC prompt (iCloud Drive, Music,
    // Documents) at launch. An NSOpenPanel choice carries intent, so macOS grants it.
    @State private var projects: [Project] = []
    /// nil = the all-projects screen; otherwise the project you are inside.
    @State private var entered: UUID?
    /// Notebook entries tag by file path, terminals by UUID, and lead boards by `lead:`.
    @State private var selection: String?
    /// Text queued to be typed into a running session, keyed by session id — how a task
    /// reaches a lead that already exists instead of starting a competing one.
    @State private var pendingInput: [UUID: String] = [:]
    /// The lines of whichever subagent `selection` currently points at. Kept apart from
    /// `CodeSession.subagents`, which only ever holds each one's status, because reading
    /// and parsing a whole transcript is only worth doing for the one actually on screen.
    @State private var subagentTranscript: [TranscriptLine] = []
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

    // ponytail: poll instead of an FSEvents watcher. The agents in the sidebar write
    // these files while you watch them; re-listing a few dozen paths every 2s is less
    // code than a recursive watcher and the tree is tiny. Revisit at thousands of files.
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            NotebookSelfTest.run()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            .frame(minWidth: 760, minHeight: 460)
            .task { restore() }
            .onReceive(tick) { _ in reload() }
        }
        .windowToolbarStyle(.unified)
    }

    private var enteredProject: Project? { projects.first { $0.id == entered } }

    // MARK: - Sidebar

    @ViewBuilder private var sidebar: some View {
        if let project = enteredProject {
            List(selection: $selection) {
                // A row rather than a toolbar icon: the way back has to be visible without
                // hunting, and a lone chevron next to the New menu is not.
                Button(action: leave) {
                    Label("All Projects", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[")

                rows(for: project)
            }
            .navigationTitle(project.name)
            .toolbar {
                Picker("Agent", selection: $agent) {
                    ForEach(AgentKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                Button(showDone ? "Hide Completed" : "Show Completed",
                       systemImage: showDone ? "eye.slash" : "eye") {
                    showDone.toggle()
                }
                Button("Describe New Feature…", systemImage: "text.bubble") {
                    startProduct("describe", in: project)
                }
                .disabled(!project.hasNotebook)
                addMenu(for: project)
            }
        } else {
            List {
                Section("Projects") {
                    ForEach(projects) { project in
                        Button { enter(project) } label: {
                            Label(project.name, systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Close Project") { close(project) } }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                Button("Open Project Folder…", systemImage: "plus", action: openProject)
                    .keyboardShortcut("n")
            }
        }
    }

    @ViewBuilder private func rows(for project: Project) -> some View {
        Section("Notebook") {
            if project.hasNotebook {
                Label("Board", systemImage: "rectangle.split.3x1")
                    .tag(boardID(project))
                OutlineGroup(NotebookLoader.display(project.entries, cards: project.cards,
                                                    showDone: showDone), children: \.children) { entry in
                    // Every known entry opens a human page first; Edit opens the raw file.
                    let card = project.cards.first { $0.url.path == entry.url.path }
                    Label(entry.title, systemImage: entry.icon)
                        .tag(entryTag(card, fallback: entry.id))
                        .contextMenu { entryMenu(entry, in: project) }
                }
            } else {
                // The shape of what the agent is about to write. Untagged, so these are
                // dimmed and unselectable until the folders exist and the tree replaces them.
                ForEach(NotebookFormat.visibleFolders, id: \.self) { folder in
                    Label(folder, systemImage: NotebookLoader.icon(forFolder: folder))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        let preview = previewRows(for: project)
        if !preview.isEmpty {
            Section("Preview") {
                ForEach(preview, id: \.id) { row in
                    Label(row.repo, systemImage: "play.rectangle")
                        .tag(row.id)
                }
            }
        }
        Section("Agents") {
            ForEach(project.sessions) { session in
                sessionRow(session, in: project)
                    .tag(sessionTag(session))
                    .contextMenu {
                        Button("Close Session") { close(session, in: project) }
                    }
            }
            if project.sessions.isEmpty {
                Label("No agents running", systemImage: agent.systemImage)
                    .foregroundStyle(.tertiary)
            }
        }
        Section("Blocks") {
            let blocks = project.blocks.filter { showDone || $0.waiting }
            ForEach(blocks) { block in
                blockRow(block).tag(blockTag(block))
            }
            if blocks.isEmpty {
                Label("Nothing waiting on you", systemImage: "checkmark.seal")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// A block names what it holds up underneath it — an approval with no context is a
    /// question you cannot answer without going to find the session that asked it.
    @ViewBuilder private func blockRow(_ block: UserBlock) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(block.title, systemImage: block.waiting
                  ? (block.isProposal ? "lightbulb" : "hand.raised") : "checkmark.circle")
                .foregroundStyle(block.waiting ? Color.primary : .secondary)
            if let task = block.task {
                Text(task)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// Right-clicking a task in the tree assigns it, without going by way of the board.
    @ViewBuilder private func entryMenu(_ entry: NotebookEntry, in project: Project) -> some View {
        if let card = project.cards.first(where: { $0.url.path == entry.url.path }), card.kind == .task {
            Button("Assign to Engineering Lead", systemImage: "person.2") {
                assign([card], in: project)
            }
            .disabled(card.status == "done" || project.assignedTaskIDs.contains(card.id))
        }
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        }
    }

    /// Agent sessions form the roots; spawned agents sit directly beneath their parent.
    /// Selecting a lead opens its orchestration board, not its underlying PTY.
    @ViewBuilder private func sessionRow(_ session: CodeSession, in project: Project) -> some View {
        let wipTaskIDs = wipTaskIDs(session, in: project)
        let subagents = visibleSubagents(session, in: project)
        if !isEngineeringLead(session) && subagents.isEmpty {
            Label(session.title, systemImage: session.icon)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(session.title, systemImage: session.icon)
                    Spacer(minLength: 4)
                    Text("\(wipTaskIDs.count) task\(wipTaskIDs.count == 1 ? "" : "s") · "
                         + "\(subagents.filter(\.running).count) running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(subagents) { subagentRow($0, in: session) }
            }
        }
    }

    private func wipTaskIDs(_ session: CodeSession, in project: Project) -> [String] {
        let done = Set(project.cards.filter { $0.kind == .task && $0.status == "done" }.map(\.id))
        let running = Subagents.runningTaskIDs(session.subagents)
        return session.taskIDs.filter { !done.contains($0) || running.contains($0) }
    }

    /// A lead spawns a specialist and a QA subagent per task, so a finished batch leaves a
    /// column of rows for work nobody is going to look at again. Once QA accepts a task and
    /// its status goes `done`, every subagent that ran for it drops off the lead — the same
    /// rule, and the same `Show Completed` escape hatch, as the tasks themselves. A
    /// subagent whose name matched no task stays: nothing said it was finished.
    private func visibleSubagents(_ session: CodeSession, in project: Project) -> [SubagentStatus] {
        guard !showDone else { return session.subagents }
        let wip = Set(wipTaskIDs(session, in: project))
        return session.subagents.filter { subagent in
            subagent.taskID.map(wip.contains) ?? true
        }
    }

    /// One line per subagent a lead has spawned — a dot while it is still running, a check
    /// once the lead's own transcript has a result for it. Clicking one always lands on
    /// that exact subagent's own parsed transcript — nothing in Claude Code's CLI can be
    /// scripted to jump straight to one specific subagent by id (`/tasks` only auto-opens
    /// a detail view when it is the *only* task running; with more than one, which is the
    /// normal case for a lead mid-batch, it shows a picker no matter what is sent to it).
    /// The terminal button is the live-TUI attempt: exact when there is just the one
    /// subagent, a list to pick from otherwise.
    private func subagentRow(_ subagent: SubagentStatus, in session: CodeSession) -> some View {
        Button {
            selection = subagentTag(session, subagent)
            reload()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.tertiary)
                Image(systemName: subagent.running ? "circle.dotted" : "checkmark.circle")
                    .foregroundStyle(subagent.running ? Color.accentColor : Color.secondary)
                Text(subagent.description)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                liveTerminalButton(subagent, in: session)
            }
            .font(.caption2)
            .padding(.leading, 14)
        }
        .buttonStyle(.plain)
        .help(subagent.agentType)
        .contextMenu {
            Button("Reveal Transcript in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([subagent.transcriptURL])
            }
        }
    }

    /// Borderless inside the row's own Button so it takes the click rather than selecting
    /// the row underneath it — the same trick the board's run button uses. Brings the
    /// lead's terminal forward and sends that CLI's own subagent picker: `/tasks` in Claude
    /// Code, `/agent` in Codex. Both are best-effort — exact with one subagent running, a
    /// list to pick from with several, since neither can be told which one to open.
    private func liveTerminalButton(_ subagent: SubagentStatus, in session: CodeSession) -> some View {
        Button {
            selection = session.id.uuidString
            pendingInput[session.id] = session.agent == .codex ? "/agent" : "/tasks"
        } label: {
            Image(systemName: "terminal")
        }
        .buttonStyle(.borderless)
        .help("Try opening in the live terminal (\(subagent.description))")
    }

    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// sidebar and the board cannot disagree about what a batch is. Also the one place that
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
        if let lead = project.sessions.first(where: { $0.title.hasPrefix("Engineering Lead") && !$0.exited }) {
            let leadAgent = lead.agent ?? .claude
            appendTaskIDs(batch.map(\.id), to: lead, in: project)
            pendingInput[lead.id] = NotebookFormat.additionalTasksPrompt(tasks: batch, sessionID: lead.id,
                                                                         agent: leadAgent)
            selection = leadTag(lead.id)
            return
        }
        // The id is minted here so the prompt can carry it: a lead that knows its own
        // session id can write it into any block it raises, and the answer comes back here.
        let id = UUID()
        addSession(agent, id: id, to: project,
                   prompt: NotebookFormat.engineeringPrompt(tasks: batch, sessionID: id, agent: agent),
                   title: "Engineering Lead", taskIDs: batch.map(\.id))
        selection = leadTag(id)
    }

    private func addMenu(for project: Project) -> some View {
        Menu("New", systemImage: "plus") {
            Section("Session") {
                Button(agent.displayName, systemImage: agent.systemImage) {
                    addSession(agent, to: project)
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
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.directory])
            }
            Button("Close Project", systemImage: "xmark") { close(project) }
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ZStack {
            // ponytail: every terminal stays mounted for the life of the app. Leaving a
            // project, switching rows, or browsing the home screen must not tear down a
            // running agent's PTY, so these are hidden rather than removed.
            ForEach(projects) { project in
                ForEach(project.sessions) { session in
                    sessionTerminal(session, in: project)
                        .opacity(isVisible(session) ? 1 : 0)
                        .allowsHitTesting(isVisible(session))
                        .accessibilityHidden(!isVisible(session))
                }
            }
            if entered == nil {
                ProjectsHome(projects: projects, enter: enter, add: openProject, close: close)
            } else if let project = needsIntake {
                // An empty project has nothing to click, so it asks what it is instead.
                ProjectIntake(project: project) { description in
                    addSession(agent, to: project,
                               prompt: NotebookFormat.onboardingPrompt(description: description),
                               title: "Notebook Setup")
                }
            } else if let project = enteredProject, selection == boardID(project) {
                boardView(for: project)
            } else if let project = enteredProject, let lead = selectedLead(in: project) {
                VStack(spacing: 0) {
                    engineeringLeadToolbar(lead, in: project)
                    Divider()
                    EngineeringLeadBoard(
                        session: lead,
                        cards: project.cards,
                        showDone: showDone,
                        openTask: { selection = taskTag($0) },
                        openSubagent: { subagent in
                            selection = subagentTag(lead, subagent)
                            reload()
                        }
                    )
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else if let project = enteredProject, let card = scopedCard(in: project, kind: .project) {
                ProjectDetail(
                    card: card,
                    cards: project.cards,
                    directory: project.directory,
                    assigned: project.assignedTaskIDs,
                    showDone: showDone,
                    open: { url in selection = NotebookEntry.id(for: url) },
                    assign: { tasks in assign(tasks, in: project) },
                    run: { card in runServices(card, in: project) },
                    openTask: { task in selection = taskTag(task.id) }
                )
                .id(card.id)
            } else if let project = enteredProject, let card = scopedCard(in: project, kind: .task) {
                TaskDetail(
                    card: card,
                    cards: project.cards,
                    assigned: project.assignedTaskIDs,
                    working: workers(on: card.id, in: project),
                    open: { url in selection = NotebookEntry.id(for: url) },
                    assign: { tasks in assign(tasks, in: project) },
                    check: { session, subagent in
                        selection = subagentTag(session, subagent)
                        reload()
                    }
                )
                .id(card.id)
            } else if let project = enteredProject, let card = scopedPageCard(in: project) {
                NotebookEntryDetail(
                    card: card,
                    cards: project.cards,
                    open: { url in selection = NotebookEntry.id(for: url) }
                )
                .id(card.id)
            } else if let project = enteredProject, let step = previewStep(in: project) {
                ProjectPreview(repo: step.repo, services: step.services,
                               run: { runServices([step], in: project) })
                    .id(selection)
            } else if let project = enteredProject, let block = selectedBlock(in: project) {
                BlockDetail(
                    block: block,
                    cards: project.cards,
                    waiting: waitingSession(for: block, in: project),
                    start: { startUnblock(block, in: project) },
                    resolve: { Blocks.resolve(block); reload() }
                )
                .id(block.id)
            } else if let project = enteredProject, let found = selectedSubagent(in: project) {
                SubagentViewer(session: found.session, subagent: found.subagent, lines: subagentTranscript)
                    .id(selection)
            } else if let entry = selectedEntry {
                NotebookEditor(entry: entry).id(entry.id)
            } else if selection == nil {
                Text("Pick a notebook entry, or start a session with +")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func sessionTerminal(_ session: CodeSession, in project: Project) -> some View {
        if isEngineeringLead(session) {
            VStack(spacing: 0) {
                engineeringLeadToolbar(session, in: project)
                Divider()
                terminal(session, in: project)
            }
        } else {
            terminal(session, in: project)
        }
    }

    private func terminal(_ session: CodeSession, in project: Project) -> some View {
        AgentTerminal(line: session.line, label: session.title,
                      pending: pendingBinding(session),
                      onExit: { markExited(session, in: project) })
    }

    private func engineeringLeadToolbar(_ session: CodeSession, in project: Project) -> some View {
        let running = Subagents.runningTaskIDs(session.subagents)
        let done = session.taskIDs.filter { taskID in
            !running.contains(taskID)
                && project.cards.contains { $0.kind == .task && $0.id == taskID && $0.status == "done" }
        }.count
        return HStack(spacing: 10) {
            Label(session.title, systemImage: session.icon)
                .font(.headline)
            NotebookStyle.pill("\(wipTaskIDs(session, in: project).count) wip")
            if done > 0 { NotebookStyle.pill("\(done) done") }
            Spacer(minLength: 12)
            Picker("Engineering Lead view", selection: engineeringLeadPane(session)) {
                ForEach(EngineeringLeadPane.allCases) { pane in Text(pane.rawValue).tag(pane) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func engineeringLeadPane(_ session: CodeSession) -> Binding<EngineeringLeadPane> {
        Binding(
            get: { selection == session.id.uuidString ? .session : .agents },
            set: { selection = $0 == .session ? session.id.uuidString : leadTag(session.id) }
        )
    }

    private func isVisible(_ session: CodeSession) -> Bool {
        entered != nil && selection == session.id.uuidString
    }

    private func isEngineeringLead(_ session: CodeSession) -> Bool {
        session.title.hasPrefix("Engineering Lead")
    }

    private func leadTag(_ id: UUID) -> String { "lead:\(id.uuidString)" }
    private func sessionTag(_ session: CodeSession) -> String {
        isEngineeringLead(session) ? leadTag(session.id) : session.id.uuidString
    }

    private func selectedLead(in project: Project) -> CodeSession? {
        project.sessions.first { isEngineeringLead($0) && leadTag($0.id) == selection }
    }

    /// A project with no notebook and no agent yet — the one case that starts a chat.
    private var needsIntake: Project? {
        enteredProject.flatMap { $0.hasNotebook || !$0.sessions.isEmpty ? nil : $0 }
    }

    private var selectedEntry: NotebookEntry? {
        guard let selection, let project = enteredProject else { return nil }
        return NotebookLoader.find(selection, in: project.entries)
    }

    /// Every subagent in this project that was dispatched for one task, whichever lead
    /// spawned it. The link is the subagent's own name, matched when it is read off disk.
    private func workers(on taskID: String, in project: Project) -> [(CodeSession, SubagentStatus)] {
        project.sessions.flatMap { session in
            session.subagents.filter { $0.taskID == taskID }.map { (session, $0) }
        }
    }

    private func subagentTag(_ session: CodeSession, _ subagent: SubagentStatus) -> String {
        "subagent:\(session.id.uuidString):\(subagent.id)"
    }

    /// The subagent `selection` currently points at, if any — matched by the tag
    /// `subagentTag` puts on each row, the same way `previewStep`/`selectedEntry` decode theirs.
    private func selectedSubagent(in project: Project) -> (session: CodeSession, subagent: SubagentStatus)? {
        guard let selection else { return nil }
        for session in project.sessions {
            if let subagent = session.subagents.first(where: { subagentTag(session, $0) == selection }) {
                return (session, subagent)
            }
        }
        return nil
    }

    // MARK: - Blocks

    private func blockTag(_ block: UserBlock) -> String { "block:\(block.id)" }

    private func selectedBlock(in project: Project) -> UserBlock? {
        project.blocks.first { blockTag($0) == selection }
    }

    /// The session this block is holding up. A block names its own session, so the answer
    /// reaches the lead that asked even with several running; one written without a
    /// session id falls back to the newest live lead, which is the single-lead case.
    private func waitingSession(for block: UserBlock, in project: Project) -> CodeSession? {
        // Nothing sits blocked on a proposal — product raised it and went home.
        guard !block.isProposal else { return nil }
        if let id = block.session {
            return project.sessions.first { $0.id == id && !$0.exited }
        }
        return project.sessions.last { $0.title.hasPrefix("Engineering Lead") && !$0.exited }
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
    }

    /// A block whose file has flipped to done is news the waiting session cannot see —
    /// it is sitting at a prompt. Typing it in is what closes the loop the user opened by
    /// pressing the button.
    private func deliverUnblocks(in project: Project) {
        for block in project.blocks where !block.waiting && !deliveredBlocks.contains(block.id) {
            guard let session = waitingSession(for: block, in: project) else { continue }
            deliveredBlocks.insert(block.id)
            pendingInput[session.id] = NotebookFormat.unblockedMessage(block: block)
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
    }

    private func persist() {
        openProjects = OpenProjects.encode(projects.map(\.directory.path))
    }

    private func enter(_ project: Project) {
        entered = project.id
        // A notebook project opens on its board, not a blank pane — nothing to click
        // otherwise until you find "Board" in the tree yourself.
        selection = project.hasNotebook ? boardID(project) : nil
        reload()
    }

    private func leave() {
        entered = nil
        selection = nil
    }

    private func close(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        persist()
        if entered == project.id { leave() }
    }

    private func boardID(_ project: Project) -> String { "board:\(project.id.uuidString)" }

    private func projectTag(_ cardID: String) -> String { "project:\(cardID)" }
    private func taskTag(_ cardID: String) -> String { "task:\(cardID)" }
    private func pageTag(_ cardID: String) -> String { "page:\(cardID)" }

    /// The tag a sidebar row selects with — known entries open a human page first.
    private func entryTag(_ card: NotebookCard?, fallback: String) -> String {
        switch card?.kind {
        case .project: return projectTag(card!.id)
        case .task: return taskTag(card!.id)
        case .roadmap, .memory, .run: return pageTag(card!.id)
        default: return fallback
        }
    }

    /// The card id out of a `projectTag`/`taskTag`, if `selection` is one of them.
    private func projectScope(_ selection: String?) -> String? {
        guard let selection, selection.hasPrefix("project:") else { return nil }
        return String(selection.dropFirst("project:".count))
    }
    private func taskScope(_ selection: String?) -> String? {
        guard let selection, selection.hasPrefix("task:") else { return nil }
        return String(selection.dropFirst("task:".count))
    }

    private func pageScope(_ selection: String?) -> String? {
        guard let selection, selection.hasPrefix("page:") else { return nil }
        return String(selection.dropFirst("page:".count))
    }

    private func scopedPageCard(in project: Project) -> NotebookCard? {
        guard let id = pageScope(selection) else { return nil }
        return project.cards.first { $0.id == id }
    }

    /// The card `selection` points at, if it is a tag of `kind`.
    private func scopedCard(in project: Project, kind: EntryKind) -> NotebookCard? {
        let scope = kind == .project ? projectScope(selection) : taskScope(selection)
        guard let scope else { return nil }
        return project.cards.first { $0.id == scope && $0.kind == kind }
    }

    private func boardView(for project: Project) -> some View {
        NotebookBoard(
            cards: project.cards,
            directory: project.directory,
            assigned: project.assignedTaskIDs,
            showDone: showDone,
            open: { url in selection = NotebookEntry.id(for: url) },
            assign: { tasks in assign(tasks, in: project) },
            review: { startProductReview(in: project) },
            run: { card in runServices(card, in: project) }
        )
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
        if let running = project.sessions.first(where: { $0.title == "Product" && !$0.exited }) {
            pendingInput[running.id] = (running.agent ?? .claude).skill("product", arguments: arguments)
            selection = running.id.uuidString
            return
        }
        addSession(agent, to: project, prompt: agent.skill("product", arguments: arguments), title: "Product")
    }

    private func previewID(_ project: Project, _ directory: URL) -> String {
        "preview:\(project.id.uuidString):\(directory.path)"
    }

    /// One sidebar row per repo actually on disk, deduped across every notebook project.
    private func previewRows(for project: Project)
        -> [(id: String, repo: String, directory: URL, services: [Service.Runnable])] {
        let steps = project.cards.filter { $0.kind == .project }
            .flatMap { Service.plan(for: $0, in: project.directory) }
        return Service.dedupedByDirectory(steps).map { step in
            (id: previewID(project, step.directory), repo: step.repo,
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

    private func reload() {
        for index in projects.indices {
            let entries = NotebookLoader.load(root: projects[index].notebookRoot)
            if entries != projects[index].entries { projects[index].entries = entries }
            // Only the project you are inside pays for reading frontmatter, or for
            // checking sessions' transcripts for subagents.
            guard projects[index].id == entered else { continue }
            let cards = NotebookIndex.load(root: projects[index].notebookRoot)
            if cards != projects[index].cards { projects[index].cards = cards }
            let blocks = Blocks.load(root: projects[index].notebookRoot)
            if blocks != projects[index].blocks { projects[index].blocks = blocks }
            deliverUnblocks(in: projects[index])
            for sIndex in projects[index].sessions.indices
                where !projects[index].sessions[sIndex].exited
                    && projects[index].sessions[sIndex].agent != nil {
                let session = projects[index].sessions[sIndex]
                let subagents = subagents(of: session, in: projects[index].directory)
                if subagents != session.subagents { projects[index].sessions[sIndex].subagents = subagents }
            }
        }
        reloadSubagentTranscript()
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

    /// Only the subagent actually on screen pays for having its transcript read and
    /// parsed — everything else is covered by the status list above.
    private func reloadSubagentTranscript() {
        guard let project = enteredProject, let found = selectedSubagent(in: project) else { return }
        let fresh = found.session.agent == .codex
            ? CodexTranscripts.transcript(at: found.subagent.transcriptURL)
            : ClaudeTranscripts.transcript(at: found.subagent.transcriptURL)
        if fresh.count != subagentTranscript.count { subagentTranscript = fresh }
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
        // Second "Engineering Lead" becomes "Engineering Lead 2" — identical sidebar rows
        // are unusable, and several leads at once is a normal thing to want.
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
        if selection == session.id.uuidString || selection == leadTag(session.id)
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
        if let scope = projectScope(selection) { return scope }
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
            switch kind {
            case .project: selection = projectTag(id)
            case .task: selection = taskTag(id)
            case .roadmap, .memory, .run: selection = pageTag(id)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func notebookRoadmap(in project: Project) -> String? {
        if let id = pageScope(selection), project.cards.contains(where: { $0.id == id && $0.kind == .roadmap }) {
            return id
        }
        let roadmaps = project.cards.filter { $0.kind == .roadmap }
        return roadmaps.count == 1 ? roadmaps[0].id : nil
    }

    private func notebookSubject(in project: Project) -> String? {
        if let id = taskScope(selection) ?? projectScope(selection) ?? pageScope(selection) { return id }
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
