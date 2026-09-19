import Foundation
import Observation
import YongkangCore

/// The window's state: the open projects, where in them the window is, and the terminals their
/// sessions run in. Screens read it and call into it; each project's own state lives in its
/// `ProjectModel`.
@MainActor @Observable final class AppModel {
    // ponytail: no folder is touched until the user picks one. Defaulting to $HOME made
    // claude scan the home folder and trip every TCC prompt (iCloud Drive, Music,
    // Documents) at launch. A folder picked in the open panel carries intent, so macOS grants it.
    private(set) var projects: [ProjectModel] = []
    /// nil = the all-projects screen; otherwise the project you are inside.
    private(set) var entered: ProjectModel?
    /// Which of the rail's sections the window is showing. The list column is that
    /// section's objects and the work area is whichever one is selected.
    var section: ConsoleSection = .overview
    /// The row the list column has selected and the page the work area shows.
    var selection: Route?
    /// Completed notebook work is historical noise until the user asks for it.
    var showDone = false
    /// What the window is telling or asking the user, until they answer it.
    var alert: AlertItem?
    /// The new-project sheet: a prompt, which is also what says where its folder goes. Here
    /// rather than in the view because the File menu opens it too, from any screen.
    var creatingProject = false
    /// The other door: a folder that already exists, picked in a panel. Same reason.
    var pickingFolder = false
    /// The agent CLIs the login shell finds on PATH, which the agent picker lists first. Nil
    /// until the first look comes back, and while it is nil no agent is shown as missing.
    private(set) var foundAgents: Set<AgentKind>?
    @ObservationIgnored private var agentLookup: Task<Void, Never>?
    private(set) var attention: [UUID: String] = [:]
    /// Every open session's terminal. Projects start a session's process when they add it, and
    /// closing the session or its project ends it; nothing on screen does either.
    let terminals: TerminalRegistry
    /// The lines of whichever agent `selection` currently points at — a subagent, or the
    /// session itself. Kept apart from `CodeSession.subagents`, which only ever holds each
    /// one's status, because reading and parsing a whole transcript is only worth doing
    /// for the one actually on screen.
    private(set) var agentTranscript: [TranscriptLine] = []
    /// The file those lines came from, so switching agents replaces them rather than
    /// leaving one agent's work under another's name when the two are the same length. The
    /// session's inspector names it too.
    private(set) var transcriptSource: URL?
    /// The safety poll behind the watchers, until `stop()`. See `start(polling:)`.
    @ObservationIgnored private var poll: Task<Void, Never>?
    /// When git was last asked, so an agent writing a file a second doesn't mean a repo-wide
    /// diff a second. See `refreshChanges`.
    @ObservationIgnored private var lastRepoRead = Date.distantPast
    /// The done tasks the window has already seen in this project. nil until the first
    /// poll seeds it, so opening a project full of finished work does not read as news.
    private var doneTasks: Set<String>?
    /// Posts the system notification for a session's question, titled, or withdraws it when the
    /// reason is nil.
    private let notify: (_ session: UUID, _ title: String, _ reason: String?) -> Void

    /// Both are for the tests, which run `/bin/sh` rather than the user's login shell, and have
    /// no app bundle for `AgentNotifications` to post from.
    init(
        terminals: TerminalRegistry? = nil,
        notify: @escaping (_ session: UUID, _ title: String, _ reason: String?) -> Void = { id, title, reason in
            if let reason {
                AgentNotifications.shared.send(sessionID: id, title: title, reason: reason)
            } else {
                AgentNotifications.shared.clear(id)
            }
        }
    ) {
        let terminals = terminals ?? TerminalRegistry()
        self.terminals = terminals
        self.notify = notify
        terminals.onExit = { [weak self] id in
            guard let self, let found = self.session(id) else { return }
            self.markExited(found.session, in: found.project)
        }
        terminals.onAttention = { [weak self] id, reason in
            // A service runner's output is nobody's question.
            guard let self, let found = self.session(id), found.session.agent != nil else { return }
            self.attentionChanged(reason, session: found.session, project: found.project)
        }
    }

    /// Looks for the agent CLIs again: at launch, and each time the picker opens, so a CLI
    /// installed while the app runs shows up without a relaunch. A look already under way
    /// answers for both.
    func lookUpAgents() {
        guard agentLookup == nil else { return }
        agentLookup = Task { [weak self] in
            let found = await AgentKind.installed()
            guard let self else { return }
            // A shell that would not start says nothing about what is installed.
            if let found { foundAgents = found }
            agentLookup = nil
        }
    }

    // MARK: - Going

    /// Where a workflow said to go. `input` only ever goes to the session `route` opens.
    func go(to destination: Destination?) {
        guard let destination else { return }
        section = destination.section
        if let route = destination.route { selection = route }
        if let input = destination.input, case .session(let id, _)? = destination.route {
            terminals.send(input, to: id)
        }
    }

    // MARK: - Watching

    /// Watches every open project and starts the safety poll behind them. Called once, when the
    /// window comes up.
    ///
    /// Almost everything that changes on screen is an agent writing a file, and FSEvents says so
    /// within 300 ms; between writes, an idle Mac is asked nothing. The beat behind that is
    /// slow and deliberate: FSEvents drops events on network volumes and across sleep, and a
    /// board that had quietly stopped updating would be a miserable bug to reproduce. `every` is
    /// injected by the tests, which are not going to wait half a minute to see it fire.
    func start(polling every: Duration = .seconds(30)) {
        for project in projects { watch(project) }
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: every)
                guard !Task.isCancelled, let self else { return }
                await reloadNow()
            }
        }
    }

    /// Ends every watch and the safety poll: the app quitting, or a test finishing.
    func stop() {
        poll?.cancel()
        poll = nil
        for project in projects { project.stopWatching() }
    }

    private func watch(_ project: ProjectModel) {
        project.startWatching { [weak self] in await self?.reloadNow() }
    }

    // MARK: - Projects

    /// The open folders, in order, as `@AppStorage("openProjects")` keeps them.
    var storedProjects: String { OpenProjects.encode(projects.map(\.directory.path)) }

    /// Reopens last session's folders, dropping any that have since been moved away.
    func restore(_ stored: String) {
        projects = OpenProjects.decode(stored)
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ProjectModel(directory: URL(fileURLWithPath: $0), terminals: terminals) }
    }

    func project(at directory: URL) -> ProjectModel? {
        projects.first { $0.directory.path == directory.path }
    }

    func project(_ id: Project.ID) -> ProjectModel? {
        projects.first { $0.id == id }
    }

    /// Adds a folder to the open projects. Check `project(at:)` first: a folder opens once.
    func open(_ directory: URL) -> ProjectModel {
        let project = ProjectModel(directory: directory, terminals: terminals)
        projects.append(project)
        watch(project)
        return project
    }

    func close(_ project: ProjectModel) {
        project.stopWatching()
        for session in project.sessions {
            attentionChanged(nil, session: session, project: project)
            terminals.terminate(session.id)
        }
        projects.removeAll { $0 === project }
        if entered === project { leave() }
    }

    func enter(_ project: ProjectModel) {
        entered = project
        doneTasks = nil
        section = .overview
        selection = .overview
        reload()
        refreshChanges(force: true)
        // Work starts from an assignment, not from opening the project — an empty project
        // opens on Overview. A session still on assigned work is what the project is doing
        // right now, so it opens on that.
        guard project.hasNotebook else { return }
        Team.seedIfAbsent(root: project.notebookRoot)
        guard project.sessions.contains(where: { $0.holdsTasks && !$0.exited }) else { return }
        section = .agents
        openSectionDefault()
    }

    func leave() {
        entered = nil
        doneTasks = nil
        selection = nil
        reload()
    }

    // MARK: - Sessions

    /// A session and the project it is open in, wherever that is.
    private func session(_ id: UUID) -> (session: CodeSession, project: ProjectModel)? {
        for project in projects {
            if let session = project.sessions.first(where: { $0.id == id }) { return (session, project) }
        }
        return nil
    }

    func attentionChanged(_ reason: String?, session: CodeSession, project: ProjectModel) {
        if reason != nil {
            guard
                projects.contains(where: {
                    $0 === project
                        && $0.sessions.contains(where: {
                            $0.id == session.id && !$0.exited
                        })
                })
            else { return }
        }
        guard attention[session.id] != reason else { return }
        attention[session.id] = reason
        notify(session.id, "\(project.name) · \(session.title)", reason)
    }

    /// Navigation only: the caller brings the app forward.
    func openAttention(_ session: CodeSession, in project: ProjectModel) {
        if entered !== project { enter(project) }
        section = .agents
        selection = .session(session.id)
    }

    func markExited(_ session: CodeSession, in project: ProjectModel) {
        guard project.markExited(session.id) else { return }
        attentionChanged(nil, session: session, project: project)
    }

    func close(_ session: CodeSession, in project: ProjectModel) {
        attentionChanged(nil, session: session, project: project)
        project.removeSession(session.id)
        switch selection {
        case .session(session.id, _)?, .subagent(session.id, _)?: selection = nil
        default: break
        }
    }

    // MARK: - Selection

    func openSectionDefault() {
        guard let project = entered else { return }
        switch section {
        case .overview:
            selection = .overview
        case .board:
            if selection?.card(in: project.snapshot.cards) == nil {
                selection = .board
            }
        case .agents:
            if selectedAgent(in: project) == nil && selectedSubagent(in: project) == nil
                && selectedSession(in: project) == nil && selectedMember(in: project) == nil
                && selection != .usage
            {
                // Assigned work first, then any agent — and a service runner only if that is all
                // there is, on its terminal, because it has no transcript to open.
                selection =
                    (project.sessions.first { $0.holdsTasks }
                    ?? project.sessions.first { $0.agent != nil }
                    ?? project.sessions.first)
                    .map { .session($0.id) }
            }
        case .review:
            // A task, not a file: what the agents did is the thing to read before any of
            // the diff means anything.
            openReview(in: project)
        case .blocks:
            // A block already open stays open, the way a card or a session does above. This
            // runs on every section change, so without it opening one block from a session's
            // board — or restoring the one you quit on — would slide straight off it onto
            // whichever block happens to be waiting first.
            guard !project.snapshot.blocks.contains(where: { selection == .block($0.id) }) else { return }
            selection =
                (project.snapshot.blocks.first(where: \.waiting)
                ?? (showDone ? project.snapshot.blocks.first : nil))
                .map { .block($0.id) }
        }
    }

    func isVisible(_ session: CodeSession) -> Bool {
        entered.map { project in
            selection == .session(session.id) || selectedSubagent(in: project)?.session.id == session.id
        } ?? false
    }

    func selectedSession(in project: ProjectModel) -> CodeSession? {
        project.sessions.first { selection == .session($0.id) }
    }

    /// The team member the selection is on. A member is a file, not a session, so it is
    /// matched by roster name, which survives the reload the same way.
    func selectedMember(in project: ProjectModel) -> TeamMember? {
        guard case .member(let name) = selection else { return nil }
        return project.snapshot.team.first { $0.name == name }
    }

    /// The agent session the selection is on, whichever of its panes is showing — its
    /// terminal included, so switching to the session does not take the pane switch away
    /// with it. A service terminal is not an agent and has no transcript to watch.
    func selectedAgent(in project: ProjectModel) -> CodeSession? {
        project.sessions.first {
            $0.agent != nil && selection?.pane(of: $0.id) != nil
        }
    }

    func selectedSubagent(in project: ProjectModel) -> (session: CodeSession, subagent: SubagentStatus)? {
        guard case .subagent(let sessionID, let id) = selection,
            let session = project.sessions.first(where: { $0.id == sessionID }),
            let subagent = session.subagents.first(where: { $0.id == id })
        else { return nil }
        return (session, subagent)
    }

    // MARK: - Reloading

    /// The read: every project's notebook, then the transcript on screen and git. Every read
    /// it starts belongs to a `ProjectReader`, so this returns before any of them land.
    ///
    /// Driven by the projects' watchers (`start(polling:)`), and by the safety beat behind them.
    func reload() { Task { await reloadNow() } }

    /// The same read, awaited — what the tests and anything that needs what it found call.
    func reloadNow() async {
        for project in projects {
            // The project you are inside pays for reading frontmatter and transcripts; on
            // the fleet screen every project does, because that screen is what it costs.
            let inside = project === entered
            let deep =
                inside || entered == nil
                || project.sessions.contains(where: { $0.agent != nil && !$0.exited })
            await project.reloadNotebook(frontmatter: deep, records: inside)
            guard deep else { continue }
            if inside {
                showFinishedWork(in: project)
                deliverUnblocks(in: project)
            }
            project.reloadSessions()
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
    private func showFinishedWork(in project: ProjectModel) {
        let done = Set(project.snapshot.cards.filter { $0.kind == .task && $0.status == "done" }.map(\.id))
        let seen = doneTasks
        if doneTasks != done { doneTasks = done }
        guard let seen, !done.subtracting(seen).isEmpty,
            selectedSession(in: project) == nil
        else { return }
        section = .review
        openReview(in: project)
    }

    /// A block whose file has flipped to done is news the waiting session cannot see —
    /// it is sitting at a prompt. Typing it in is what closes the loop the user opened by
    /// pressing the button.
    private func deliverUnblocks(in project: ProjectModel) {
        for block in project.snapshot.blocks where !block.waiting && !project.deliveredBlocks.contains(block.id) {
            guard let session = project.waitingSession(for: block) else { continue }
            project.deliveredBlocks.insert(block.id)
            go(
                to: Destination(
                    section: .agents, route: .session(session.id),
                    input: NotebookFormat.unblockedMessage(block: block)))
        }
    }

    /// git is only asked while a screen that shows its answer is open, and no more often than
    /// every 6 s — an agent writing a file a second must not mean a repo-wide diff a second.
    /// That was every third 2 s tick before the timer went; it is the same beat, counted in
    /// seconds now that the reads arrive when the disk says so rather than on a clock.
    func refreshChanges(force: Bool = false) {
        // Every section, not only Review: the rail's light says work is waiting for approval,
        // and it has to come on while you are looking at the board.
        guard let project = entered else { return }
        guard force || Date().timeIntervalSince(lastRepoRead) >= 6 else { return }
        lastRepoRead = Date()
        // Only Overview and Review show line counts, so only they pay for opening untracked
        // files to count them. The light on the rail needs the file list, not its lines.
        let countingLines = section == .overview || section == .review
        Task { await project.refreshRepo(countingLines: countingLines) }
    }

    /// Review opens on the first task waiting for approval, as git sees the tree. The read
    /// this starts answers a moment later, so the page is picked now from the last read and
    /// picked again once the new one is in, unless the user has already moved on.
    private func openReview(in project: ProjectModel) {
        selection = project.firstReview
        let landed = selection
        Task {
            await project.refreshRepo()
            guard entered === project, selection == landed else { return }
            selection = project.firstReview
        }
    }

    /// Only the agent actually on screen pays for having its transcript read and parsed —
    /// everything else is covered by the status list above.
    func reloadAgentTranscript() {
        // Only when the work area is showing the agent's transcript pane.
        guard let project = entered, let watched = selectedAgent(in: project),
            selection?.pane(of: watched.id) == .transcript, let provider = watched.agent?.provider
        else {
            transcriptSource = nil
            agentTranscript = []
            return
        }
        // The provider looks for the file off the main thread and the reader parses it there,
        // and by the time they answer the window may be showing another agent.
        let asked = selection
        Task {
            let url = await provider.transcriptURL(session: watched.id, project: project.directory)
            guard selection == asked else { return }
            var fresh: [TranscriptLine] = []
            if let url { fresh = await project.reader.transcript(of: provider, at: url) }
            guard selection == asked else { return }
            guard url != transcriptSource || fresh.count != agentTranscript.count else { return }
            transcriptSource = url
            agentTranscript = fresh
        }
    }
}
