import Foundation

/// A project is a folder. Its agents run there, its notebook lives in `.notebook/`
/// inside it, and both are only ever reachable through the project.
package struct Project: Identifiable, Equatable, Sendable {
    /// Minted by the caller that keeps the project, so every value built from it has the
    /// same identity: hover, lists and the entered project all key on it.
    package let id: UUID
    package let directory: URL
    package var entries: [NotebookEntry] = []
    /// Frontmatter for the board, read only while you are inside the project.
    package var cards: [NotebookCard] = []
    /// What the agents need from the user before they can go on, read the same way.
    package var blocks: [UserBlock] = []
    /// The project's named agents, from `.notebook/team/` (shipped defaults until that
    /// folder exists). Read the same way — the folder tree is the state.
    package var team: [TeamMember] = Team.defaults
    package var sessions: [CodeSession] = []
    /// Gates, by id, the app has handed to an agent to work through with the user. In memory
    /// only, so a relaunch puts a half-finished one back on the desk — see `ProjectModel`.
    package var guided: Set<String> = []
    /// Every assigned session's reports on disk, by session id — including sessions that are
    /// closed or ran before a relaunch, whose finished work may still be waiting for review.
    package var records: [UUID: LeadCoordination] = [:]
    /// The other open project each session here is talking to, by session id. In memory only,
    /// like `guided` — see `ProjectModel.peers`.
    package var peers: [UUID: Peer] = [:]
    /// The name of the request each Product session here is on, by session id. In memory only,
    /// like `peers` — see `ProjectModel.requestName`.
    package var requests: [UUID: String] = [:]

    package init(
        id: UUID = UUID(),
        directory: URL,
        entries: [NotebookEntry] = [],
        cards: [NotebookCard] = [],
        blocks: [UserBlock] = [],
        team: [TeamMember] = Team.defaults,
        sessions: [CodeSession] = [],
        guided: Set<String> = [],
        records: [UUID: LeadCoordination] = [:],
        peers: [UUID: Peer] = [:],
        requests: [UUID: String] = [:]
    ) {
        self.id = id
        self.directory = directory
        self.entries = entries
        self.cards = cards
        self.blocks = blocks
        self.team = team
        self.sessions = sessions
        self.guided = guided
        self.records = records
        self.peers = peers
        self.requests = requests
    }

    package var onlineAgentCount: Int {
        sessions.filter { $0.agent != nil }.reduce(0) {
            $0 + ($1.exited ? 0 : 1) + $1.activeSubagents.count
        }
    }

    package var name: String { directory.lastPathComponent }
    package var notebookRoot: URL { NotebookFormat.root(in: directory) }
    /// No `.notebook` on disk means no entries — the folder is left untouched.
    package var hasNotebook: Bool { !entries.isEmpty }
    package var pageCount: Int { NotebookLoader.pageCount(entries) }
    /// Tasks an open session already has. The WIP set: assigning again while a session is
    /// still on a task would just hand it to a second one.
    package var assignedTaskIDs: Set<String> { Project.assignedTaskIDs(in: sessions) }

    /// The same set off a bare session list, for a caller that is still building the project
    /// its cards go into — see `ProjectModel.value`.
    package static func assignedTaskIDs(in sessions: [CodeSession]) -> Set<String> {
        Set(sessions.filter { !$0.exited }.flatMap(\.taskIDs))
    }
}

/// The open project list, as it survives a relaunch. Paths, not bookmarks: the app is
/// not sandboxed, so a path is enough to reopen a folder the user already picked.
package enum OpenProjects {
    package static func encode(_ paths: [String]) -> String {
        guard let data = try? JSONEncoder().encode(paths) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    package static func decode(_ text: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }
}

/// Which group each open project sits in, by path, as it survives a relaunch. A project with
/// no entry here is loose. A group is a name carried by the projects in it rather than a thing
/// of its own, so an empty group cannot be written down — or exist. The order is still
/// `OpenProjects`: the projects of one group are the run of neighbours that name it.
package enum ProjectGroups {
    package static func encode(_ groups: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(groups) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    package static func decode(_ text: String) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(text.utf8))) ?? [:]
    }
}

/// The agent sessions each open project had, as they survive a quit or a crash, by project
/// path. Only what starts one again: the rest is read back off the notebook and the CLI's own
/// files. Services are left out — the user starts those.
package enum OpenSessions {
    package struct Stored: Codable, Equatable, Sendable {
        package let id: UUID
        package let title: String
        package let icon: String
        /// The line it was started with, to start it over when there is nothing to resume.
        package let line: String
        package let agent: AgentKind
        package let taskIDs: [String]
        package let reading: [String]
    }

    package static func stored(_ sessions: [CodeSession]) -> [Stored] {
        sessions.compactMap { session in
            session.agent.map {
                Stored(
                    id: session.id, title: session.title, icon: session.icon, line: session.line, agent: $0,
                    taskIDs: session.taskIDs, reading: session.reading.map(\.path))
            }
        }
    }

    package static func encode(_ sessions: [String: [Stored]]) -> String {
        guard let data = try? JSONEncoder().encode(sessions) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    package static func decode(_ text: String) -> [String: [Stored]] {
        (try? JSONDecoder().decode([String: [Stored]].self, from: Data(text.utf8))) ?? [:]
    }

    /// The line that reopens `session` with its conversation, or the one it was first started
    /// with when its CLI kept nothing to resume.
    package static func line(resuming session: Stored, in directory: URL) async -> String {
        guard
            let words = await session.agent.provider.resume(
                sessionID: session.id, project: directory, noCommit: !session.taskIDs.isEmpty,
                reading: session.agent.provider.readsOtherFolders ? session.reading : [])
        else { return session.line }
        let command = ([session.agent.command] + words).joined(separator: " ")
        return "cd \(AgentCommand.quoted(directory.path)) && exec \(command)"
    }
}

/// A terminal in the sidebar. It holds the shell line rather than an agent, because a
/// running service is the same thing to the window: a PTY in a directory.
package struct CodeSession: Identifiable, Equatable, Sendable {
    package let id: UUID
    package let title: String
    package let icon: String
    package let line: String
    /// Nil for service terminals; agent sessions keep their provider so follow-up skill
    /// prompts still use the right syntax after the toolbar selection changes.
    package let agent: AgentKind?
    /// The icon a plain shell is started with, which is what tells it from a service runner.
    package static let terminalIcon = "terminal"
    /// A plain shell the user opened, rather than an agent or a service.
    package var isTerminal: Bool { agent == nil && icon == Self.terminalIcon }
    /// Tasks this session was handed, in the order it was given them. Empty for a session
    /// nobody assigned work to.
    package var taskIDs: [String] = []
    /// Set once the underlying process exits — a dead session is never routed more work.
    package var exited: Bool = false
    /// Its turn is over and the next word is yours, as its transcript last read
    /// (`AgentState.of`). A CLI that answers in prose rather than at a prompt gives no other
    /// sign that it has stopped, and a session taken for working when nothing is running is
    /// one the user waits on for ever.
    package var idle: Bool = false
    /// Descendants discovered from the provider's on-disk transcripts.
    package var subagents: [SubagentStatus] = []
    /// The reports this session filed against its tasks, including completed work.
    package var coordination: LeadCoordination? = nil
    /// Folders beyond its project it was given to read — another project's repo, usually.
    package var reading: [URL] = []

    /// The ones still working. A finished agent has nothing left to watch, so the session's
    /// lists drop it; its transcript stays reachable from the task it was dispatched for.
    package var activeSubagents: [SubagentStatus] { subagents.filter(\.running) }

    /// Explicit, rather than the synthesized memberwise init, because `id` needs to be
    /// settable: the caller has to hand in the same UUID it passed Claude Code as
    /// `--session-id`, so this row's id is the key that finds that session's transcript.
    package init(
        id: UUID = UUID(), title: String, icon: String, line: String, agent: AgentKind? = nil,
        taskIDs: [String] = [], exited: Bool = false, idle: Bool = false,
        subagents: [SubagentStatus] = [], coordination: LeadCoordination? = nil, reading: [URL] = []
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.line = line
        self.agent = agent
        self.taskIDs = taskIDs
        self.exited = exited
        self.idle = idle
        self.subagents = subagents
        self.coordination = coordination
        self.reading = reading
    }
}

extension CodeSession {
    /// A session assigned tasks, which is what has a result to review and is refused commits.
    /// Not the title: an assigned session is named after its coding agent, like a plain one.
    package var holdsTasks: Bool { !taskIDs.isEmpty }
}
