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
    var sessions: [CodeSession]
    /// What the user has written about each task under review, by task id, until they send
    /// it or approve. Lives here rather than in the page so leaving for a diff keeps it.
    var reviewDrafts: [String: ReviewDraft] = [:]
    /// Blocks, by id, whose clearing the waiting session has already been told about, so the
    /// poll says so once rather than on every tick. A workflow that clears a block with its own
    /// message records it here too, or the poll would type "Unblocked" over it.
    var deliveredBlocks: Set<String> = []

    /// With no snapshot, only the file list is read: the rest comes with the first poll
    /// that looks inside the project.
    init(directory: URL, snapshot: NotebookSnapshot? = nil, sessions: [CodeSession] = []) {
        self.directory = directory
        self.snapshot =
            snapshot ?? NotebookSnapshot(entries: NotebookLoader.load(root: NotebookFormat.root(in: directory)))
        self.sessions = sessions
    }

    /// The project as the one value the screens and Core's readers take. Reading it observes
    /// this project's notebook and sessions, and nothing of any other project.
    var value: Project {
        Project(
            id: id, directory: directory, entries: snapshot.entries, cards: snapshot.cards,
            blocks: snapshot.blocks, team: snapshot.team, sessions: sessions, records: snapshot.records)
    }

    var name: String { value.name }
    var notebookRoot: URL { value.notebookRoot }
    var hasNotebook: Bool { value.hasNotebook }
    var assignedTaskIDs: Set<String> { value.assignedTaskIDs }

    // ponytail: derived on every read, as `ChangeSummary.of` was at each of its call sites.
    // Store it when the snapshot, sessions or repo change if a profile ever shows the cost.
    var summary: ChangeSummary { ChangeSummary.of(value, changes: repo.changes) }

    /// The task page to land on: the first one waiting for approval, or the whole working
    /// tree when nothing is.
    var firstReview: Route {
        summary.waiting.first.map { .reviewTask($0.id) } ?? .review(file: nil)
    }

    // MARK: - Reloading

    /// See `NotebookSnapshot.reread` for what `frontmatter` and `records` add.
    func reloadNotebook(frontmatter: Bool, records: Bool) {
        let fresh = snapshot.reread(root: notebookRoot, frontmatter: frontmatter, records: records)
        if fresh != snapshot { snapshot = fresh }
    }

    /// What each agent session has spawned and recorded since the last poll.
    func reloadSessions() {
        for index in sessions.indices where sessions[index].agent != nil {
            let session = sessions[index]
            if !session.exited {
                let subagents = subagents(of: session)
                if subagents != session.subagents { sessions[index].subagents = subagents }
            }
            guard !session.taskIDs.isEmpty else { continue }
            let coordination = LeadCoordination.load(root: notebookRoot, session: sessions[index])
            if coordination != session.coordination {
                sessions[index].coordination = coordination
            }
        }
        // Written from the poll rather than from the usage screen: what an agent spent
        // has to survive a run in which nobody opened that screen, and the transcripts
        // it is read from are no longer findable once the sessions are gone.
        UsageLedger.record(AgentUsage.spends(in: value), root: notebookRoot)
    }

    func refreshRepo() {
        // A project the agents work in needs a repository: without one there is no diff to
        // review and nowhere for an approval to commit. Created, never committed to.
        if hasNotebook && !GitChanges.isRepository(directory) {
            _ = GitChanges.initialize(in: directory)
        }
        let fresh = RepoStatus.read(in: directory)
        if fresh != repo { repo = fresh }
    }

    /// Each provider writes its subagents somewhere else — Claude Code beside the parent
    /// session, Codex as sibling rollouts pointing back at it — so the session's own agent
    /// picks the reader. A service terminal has neither and is skipped by the caller.
    private func subagents(of session: CodeSession) -> [SubagentStatus] {
        let found: [SubagentStatus]
        switch session.agent {
        case .codex:
            found = CodexTranscripts.subagents(
                sessionID: session.id, projectDirectory: directory,
                taskIDs: session.taskIDs)
        case .claude:
            found = ClaudeTranscripts.subagents(
                sessionID: session.id, projectDirectory: directory,
                taskIDs: session.taskIDs)
        default:
            found = []
        }
        // Named here rather than in either reader: the roster is project state, and the
        // screens downstream should never each have to look a running agent up themselves.
        return found.map { $0.named(in: snapshot.team) }
    }

    // MARK: - Sessions

    /// `id` is generated up front so the same id names both the CLI's `--session-id` and
    /// this session's own row — that is what lets its transcript be found again later, and
    /// what a caller passes in when the prompt itself has to name the session.
    ///
    /// Returns the new session's terminal, because a new session opens on its live CLI.
    func addSession(
        _ agent: AgentKind, id: UUID = UUID(), prompt: String? = nil, title: String? = nil, taskIDs: [String] = []
    ) -> Route {
        addSession(
            id: id, title: title ?? agent.displayName, icon: agent.systemImage,
            line: AgentCommand.line(
                directory: directory.path,
                agent: agent, prompt: prompt, sessionID: id,
                brief: title?.hasPrefix("Engineering Lead") == true,
                noCommit: title?.hasPrefix("Engineering Lead") == true),
            agent: agent, taskIDs: taskIDs)
        return .session(id)
    }

    func addSession(
        id: UUID, title: String, icon: String, line: String,
        agent: AgentKind? = nil, taskIDs: [String] = []
    ) {
        // Second "Engineering Lead" becomes "Engineering Lead 2" — identical rows are
        // unusable, and several leads at once is a normal thing to want.
        let taken = sessions.filter { $0.title == title || $0.title.hasPrefix(title + " ") }.count
        let name = taken == 0 ? title : "\(title) \(taken + 1)"
        sessions.append(
            CodeSession(
                id: id, title: name, icon: icon, line: line,
                agent: agent, taskIDs: taskIDs))
    }

    func removeSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    /// False when this project no longer has the session, so there is nothing to clear.
    func markExited(_ id: UUID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
        sessions[index].exited = true
        return true
    }

    func appendTaskIDs(_ ids: [String], to id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].taskIDs += ids
    }

    /// The session this block is holding up. A block names its own session, so the answer
    /// reaches the lead that asked even with several running; one written without a
    /// session id falls back to the newest live lead, which is the single-lead case.
    func waitingSession(for block: UserBlock) -> CodeSession? {
        // A proposal links to Product, but does not block an engineering session.
        guard !block.isProposal else { return nil }
        if let id = block.session {
            return sessions.first { $0.id == id && !$0.exited }
        }
        return sessions.last { $0.isEngineeringLead && !$0.exited }
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
