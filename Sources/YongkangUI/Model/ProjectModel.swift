import Foundation
import Observation
import YongkangCore

/// One open project: its notebook as the agents last left it, what git says about its
/// working tree, and the sessions running in it. An object per project, so a poll that
/// changes this project re-renders the screens that read it and no other project's.
///
/// The notebook and the repo are immutable values, replaced whole and only when a fresh
/// read differs. This class is where they change; nothing else writes them.
@MainActor @Observable final class ProjectModel: Identifiable {
    let id = UUID()
    let directory: URL
    private(set) var snapshot: NotebookSnapshot
    /// What the agents changed on disk, read from git. Only refreshed while you are inside
    /// the project — a repo-wide diff of every open project would be rude.
    private(set) var repo = RepoStatus()
    /// When git was last asked about this project. See `repoReadIsDue`.
    @ObservationIgnored private var lastRepoRead = Date.distantPast
    /// Repo reads started, and the newest of them whose answer `repo` holds. See `refreshRepo`.
    @ObservationIgnored private var repoReads = 0
    @ObservationIgnored private var repoShown = 0
    var sessions: [CodeSession]
    /// What the user has written about each task under review, by task id, until they send
    /// it or approve. Lives here rather than in the page so leaving for a diff keeps it.
    var reviewDrafts: [String: ReviewDraft] = [:]
    /// Blocks, by id, whose clearing the waiting session has already been told about, so the
    /// poll says so once rather than on every tick. A workflow that clears a block with its own
    /// message records it here too, or the poll would type "Unblocked" over it.
    var deliveredBlocks: Set<String> = []
    /// The agents whose CLI's own record doesn't allow it in this folder yet: a session of one
    /// would ask before anything else. See `readTrust`.
    private(set) var untrusted: Set<AgentKind> = []
    /// The session opened only for that question, until it is answered. See `askToTrust`.
    var trustSession: UUID?
    /// Each CLI's record of whether it may work in a folder. The tests stand in for it.
    @ObservationIgnored var trustRecord: (AgentKind, URL) async -> Bool? = { await $0.provider.trusts($1) }
    /// Where a session added here runs. Nil runs nothing: the session is only a row, as in
    /// the workflow tests.
    private let terminals: TerminalRegistry?
    /// Every read this project makes, off the main actor. See `ProjectReader`.
    @ObservationIgnored let reader: ProjectReader
    /// This project's folders, watched rather than polled. See `FSEventWatcher`.
    @ObservationIgnored private let watcher: FSEventWatcher
    /// The loop turning what the watcher says into a reload, until `stopWatching()`.
    @ObservationIgnored private var watch: Task<Void, Never>?
    /// What the usage screen reads, as one value: its sessions and subagents, and the sizes of
    /// the files their spend is parsed out of. It is the whole reason that screen no longer
    /// keeps a two-second `stat` loop of its own — see `ProjectReader.watch(of:)`.
    private(set) var usageSignature = ""
    /// The poll's read of the notebook, while it is still going.
    @ObservationIgnored private var notebookRead: Task<Void, Never>?
    /// The poll's read of what the sessions spawned and spent, while it is still going.
    @ObservationIgnored private var sessionsRead: Task<Void, Never>?

    /// With no snapshot, only the file list is read: the rest comes with the first poll
    /// that looks inside the project.
    init(
        directory: URL, snapshot: NotebookSnapshot? = nil, sessions: [CodeSession] = [],
        terminals: TerminalRegistry? = nil
    ) {
        self.directory = directory
        self.snapshot =
            snapshot ?? NotebookSnapshot(entries: NotebookLoader.load(root: NotebookFormat.root(in: directory)))
        self.sessions = sessions
        self.terminals = terminals
        self.reader = ProjectReader(directory: directory)
        // `.git/objects` is rewritten by every git command an agent runs, and none of it
        // changes what `git status` says, so those writes never reach the watcher at all.
        self.watcher = FSEventWatcher(excluding: [directory.appendingPathComponent(".git/objects")])
        resummarize()
    }

    // MARK: - Watching

    /// Starts watching this project, and calls `changed` whenever anything under it — or under
    /// a live session's transcript folder — is written.
    ///
    /// `changed` is awaited inside the loop, so a burst landing while it runs becomes one more
    /// call rather than a queue of them. That is what the stream's `.bufferingNewest(1)` is for.
    /// Starting twice does nothing: the projects restored at launch are already watched.
    func startWatching(_ changed: @escaping @Sendable @MainActor () async -> Void) {
        guard watch == nil else { return }
        // The tree is watchable straight away; the session folders arrive with the first read
        // that asks each provider where its CLI keeps them.
        watcher.watch([directory])
        let changes = watcher.changes
        watch = Task { for await _ in changes { await changed() } }
    }

    /// Ends the watch. Explicit, called when the project is closed or the app quits, because a
    /// `@MainActor` class's `deinit` is nonisolated and could not touch any of this.
    func stopWatching() {
        watch?.cancel()
        watch = nil
        watcher.stop()
    }

    /// The folders to watch, asked for again because the sessions changed. Only the watch —
    /// the reads that go with it are `reloadSessions`', and a session that has just been added
    /// has nothing on disk to read yet.
    private func rewatch() {
        Task { [reader] in self.watcher.watch(await reader.watch(of: self.value).folders) }
    }

    /// The project as the one value the screens and Core's readers take. Reading it observes
    /// this project's notebook and sessions, and nothing of any other project.
    var value: Project {
        Project(
            id: id, directory: directory, entries: snapshot.entries, cards: cards,
            blocks: snapshot.blocks, team: snapshot.team, sessions: sessions, records: snapshot.records)
    }

    /// What the screens draw, rather than what the files say: the snapshot's cards with any
    /// task nobody is on any more settled back into the queue. See `NotebookIndex.settled`.
    /// The snapshot itself stays as it was read, so the poll still compares like with like.
    var cards: [NotebookCard] {
        NotebookIndex.settled(snapshot.cards, assigned: assignedTaskIDs, blocked: blockedTaskIDs)
    }

    /// The tasks an open block names. Not proposals: those hold up the notebook, not a task.
    var blockedTaskIDs: Set<String> {
        Set(snapshot.blocks.waitingOnUser.filter { !$0.isProposal }.compactMap(\.task))
    }

    var name: String { value.name }
    var notebookRoot: URL { value.notebookRoot }
    var hasNotebook: Bool { value.hasNotebook }
    var assignedTaskIDs: Set<String> { Project.assignedTaskIDs(in: sessions) }

    /// What the agents just finished, derived from the notebook, the sessions and git —
    /// never in a view body. Re-derived here whenever one of those three changes, which is
    /// the only time it can differ, and published only when it does.
    private(set) var summary = ChangeSummary()

    /// Every project card's repos and what runs under each, detected off the main actor when
    /// the cards change. The repo list, the Run button and the preview all read it.
    private(set) var services: [ServicePlan] = []

    /// The repos one project card lists, in the order it lists them.
    func services(of card: NotebookCard) -> [ServicePlan] {
        services.filter { $0.card == card.id }
    }

    private func resummarize() {
        let fresh = ChangeSummary.of(value, changes: repo.changes)
        if fresh != summary { summary = fresh }
    }

    /// The task page to land on: the first one waiting for approval, or the whole working
    /// tree when nothing is.
    var firstReview: Route {
        summary.waiting.first.map { .reviewTask($0.id) } ?? .review(file: nil)
    }

    // MARK: - Reloading

    /// The notebook read again by this project's reader, and published only if it differs.
    /// See `NotebookSnapshot.reread` for what `frontmatter` and `records` add.
    ///
    /// A poll that lands while the last read is still going joins it rather than starting a
    /// second read of the same files beside it, so the reads can never pile up behind a slow
    /// disk. Returns once `snapshot` holds that read.
    func reloadNotebook(frontmatter: Bool, records: Bool) async {
        if let notebookRead { return await notebookRead.value }
        let read = Task { [snapshot, reader, directory] in
            guard let fresh = await reader.notebook(after: snapshot, frontmatter: frontmatter, records: records)
            else { return }
            self.snapshot = fresh
            self.resummarize()
            // The repos a project card lists only change with the cards, and finding what runs
            // under each opens files. Detected here, once, rather than on every render.
            guard fresh.cards != snapshot.cards else { return }
            let plans = await Service.plans(for: fresh.cards, in: directory)
            if plans != self.services { self.services = plans }
        }
        notebookRead = read
        await read.value
        notebookRead = nil
    }

    /// Asks each CLI's own record again whether it may work here. One that can't be read right
    /// now leaves its agent as it was.
    ///
    /// ponytail: Claude Code's record is the whole of `~/.claude.json`, parsed on every reload of
    /// every project. Skip the parse while the file's modification date holds, if it ever shows
    /// in a profile.
    func readTrust() async {
        var untrusted = self.untrusted
        for agent in AgentKind.allCases {
            guard let trusted = await trustRecord(agent, directory) else { continue }
            if trusted { untrusted.remove(agent) } else { untrusted.insert(agent) }
        }
        if untrusted != self.untrusted { self.untrusted = untrusted }
    }

    /// What each agent session has spawned and recorded since the last poll. The reader reads
    /// the files off the main actor, so this starts that read and returns. A poll that lands
    /// while the last read is still going starts nothing, rather than a second read of the
    /// same files beside it.
    func reloadSessions() {
        guard sessionsRead == nil else { return }
        sessionsRead = Task { [value, reader] in
            let reads = await reader.sessions(of: value)
            self.apply(reads)
            // Where each live session's CLI keeps its files is the same question as which
            // folders to watch and what the usage screen has to notice, so it is asked once.
            // The watcher leaves its stream alone when the folders come back unchanged.
            let watch = await reader.watch(of: self.value)
            self.watcher.watch(watch.folders)
            if watch.usage != self.usageSignature { self.usageSignature = watch.usage }
            self.sessionsRead = nil
        }
    }

    /// What one poll found, written back by session id rather than by index: a session can be
    /// closed, or another added, while the providers read.
    private func apply(_ reads: [SessionRead]) {
        var changed = false
        for read in reads {
            guard let index = sessions.firstIndex(where: { $0.id == read.id }) else { continue }
            if let subagents = read.subagents, subagents != sessions[index].subagents {
                sessions[index].subagents = subagents
                changed = true
            }
            if read.readRecords, read.coordination != sessions[index].coordination {
                sessions[index].coordination = read.coordination
                changed = true
            }
        }
        if changed { resummarize() }
    }

    /// Whether git may be asked about this project again: at most every 6 s, unless `force`.
    /// Answering yes starts the next wait.
    func repoReadIsDue(force: Bool = false, now: Date = Date()) -> Bool {
        guard force || now.timeIntervalSince(lastRepoRead) >= 6 else { return false }
        lastRepoRead = now
        return true
    }

    /// Reads git off the main thread and publishes what it found, if it differs. Returns once
    /// `repo` holds this read, or a newer one. `countingLines` is for a screen that shows
    /// untracked files' line counts; see `RepoStatus.read`.
    func refreshRepo(countingLines: Bool = true) async {
        await refreshRepo { [repo, hasNotebook, reader] in
            await reader.repo(after: repo, countingLines: countingLines, initializing: hasNotebook)
        }
    }

    /// `read` is the git read itself; tests stand in for it to make one answer arrive late.
    ///
    /// Reads overlap — the poll, a forced refresh, the one after a commit — and git can answer
    /// them in any order. Each read is numbered when it starts, and an answer is only shown if
    /// it is newer than the one on screen, so a slow early read never overwrites a later one.
    /// A newest-only rule would do that too, but a poll that keeps starting reads faster than
    /// git answers would then never show any.
    ///
    /// A cancelled read is dropped too: its git was terminated, and what came back is an
    /// empty tree, not the repo.
    func refreshRepo(_ read: () async -> RepoStatus) async {
        repoReads += 1
        let request = repoReads
        let fresh = await read()
        guard request > repoShown, !Task.isCancelled else { return }
        repoShown = request
        guard fresh != repo else { return }
        repo = fresh
        resummarize()
    }

    // MARK: - Sessions

    /// `id` is generated up front so the same id names both the CLI's `--session-id` and
    /// this session's own row — that is what lets its transcript be found again later, and
    /// what a caller passes in when the prompt itself has to name the session.
    ///
    /// Returns the new session's terminal, because a new session opens on its live CLI.
    /// `reading` is the folders beyond this one the agent is handed, for a CLI that takes any.
    func addSession(
        _ agent: AgentKind, id: UUID = UUID(), prompt: String? = nil, title: String? = nil, taskIDs: [String] = [],
        reading: [URL] = []
    ) -> Route {
        let reading = agent.provider.readsOtherFolders ? reading : []
        addSession(
            id: id, title: title ?? agent.displayName, icon: agent.systemImage,
            line: AgentCommand.line(
                directory: directory.path,
                agent: agent, prompt: prompt, sessionID: id, noCommit: !taskIDs.isEmpty, reading: reading.map(\.path)),
            agent: agent, taskIDs: taskIDs, reading: reading)
        return .session(id)
    }

    func addSession(
        id: UUID, title: String, icon: String, line: String,
        agent: AgentKind? = nil, taskIDs: [String] = [], reading: [URL] = []
    ) {
        // A second "Product" becomes "Product 2" — identical rows are unusable, and two
        // sessions on the same kind of work at once is a normal thing to want.
        let taken = sessions.filter { $0.title == title || $0.title.hasPrefix(title + " ") }.count
        let name = taken == 0 ? title : "\(title) \(taken + 1)"
        let session = CodeSession(
            id: id, title: name, icon: icon, line: line, agent: agent, taskIDs: taskIDs, reading: reading)
        sessions.append(session)
        // Every session starts here, so this one event counts them all. A service runner has no agent.
        Analytics.capture("session_started", ["agent": agent?.rawValue ?? "service", "tasks": taskIDs.count])
        resummarize()
        terminals?.start(session, in: directory)
        // So the new agent's transcript folder is watched now rather than at the next safety
        // beat. A CLI that names its transcript after the session id (every one but Codex, which
        // has to be found by reading its rollouts) is watchable before it has written a byte.
        rewatch()
    }

    /// Ends the session's process along with its row: a closed session has no one to stop it later.
    func removeSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        resummarize()
        terminals?.terminate(id)
    }

    /// False when this project no longer has the session, so there is nothing to clear.
    func markExited(_ id: UUID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
        sessions[index].exited = true
        resummarize()
        return true
    }

    /// The session this block is holding up. A block names its own session, so the answer
    /// reaches the one that asked even with several running; one written without a session
    /// id falls back to the newest live session holding the task it names, then any.
    func waitingSession(for block: UserBlock) -> CodeSession? {
        // A proposal links to Product, but does not block an assigned session.
        guard !block.isProposal else { return nil }
        if let id = block.session {
            return sessions.first { $0.id == id && !$0.exited }
        }
        let live = sessions.filter { $0.holdsTasks && !$0.exited }
        return live.last { session in block.task.map { session.taskIDs.contains($0) } ?? false } ?? live.last
    }
}

/// Where a workflow leaves the window, for the view to apply. A workflow decides where to go
/// but doesn't go there itself, so it can be tested with no window, and `section` and
/// `selection` are written in one place.
struct Destination: Equatable {
    var section: ConsoleSection
    /// Nil leaves the selection as it was.
    var route: Route?
    /// A follow-up for the session `route` opens, typed into its terminal like any other.
    var input: String?
}
