import Foundation

/// A project is a folder. Its agents run there, its notebook lives in `.notebook/`
/// inside it, and both are only ever reachable through the project.
package struct Project: Identifiable, Equatable {
    /// Minted by the caller that keeps the project, so every value built from it has the
    /// same identity: hover, lists and the entered project all key on it.
    package let id: UUID
    package let directory: URL
    package var entries: [NotebookEntry] = []
    /// Frontmatter for the board, read only while you are inside the project.
    package var cards: [NotebookCard] = []
    /// What the agents need from the user before they can go on, read the same way.
    package var blocks: [UserBlock] = []
    /// The Engineering Lead's named specialists, from `.notebook/team/` (shipped defaults
    /// until that folder exists). Read the same way — the folder tree is the state.
    package var team: [TeamMember] = Team.defaults
    package var sessions: [CodeSession] = []
    /// Every lead's run records on disk, by session id — including leads that are closed or
    /// ran before a relaunch, whose finished work may still be waiting for review.
    package var records: [UUID: LeadCoordination] = [:]

    package init(
        id: UUID = UUID(),
        directory: URL,
        entries: [NotebookEntry] = [],
        cards: [NotebookCard] = [],
        blocks: [UserBlock] = [],
        team: [TeamMember] = Team.defaults,
        sessions: [CodeSession] = [],
        records: [UUID: LeadCoordination] = [:]
    ) {
        self.id = id
        self.directory = directory
        self.entries = entries
        self.cards = cards
        self.blocks = blocks
        self.team = team
        self.sessions = sessions
        self.records = records
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
    /// Tasks an open session already has. The WIP set: assigning again while a lead is
    /// still on a task would just hand it to a second one.
    package var assignedTaskIDs: Set<String> {
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

/// A terminal in the sidebar. It holds the shell line rather than an agent, because a
/// running service is the same thing to the window: a PTY in a directory.
package struct CodeSession: Identifiable, Equatable {
    package let id: UUID
    package let title: String
    package let icon: String
    package let line: String
    /// Nil for service terminals; agent sessions keep their provider so follow-up skill
    /// prompts still use the right syntax after the toolbar selection changes.
    package let agent: AgentKind?
    /// Tasks this session was handed, in the order it was given them. Empty for anything
    /// that is not an Engineering Lead — a plain session was not assigned work.
    package var taskIDs: [String] = []
    /// Set once the underlying process exits — a dead session is never routed more work.
    package var exited: Bool = false
    /// Descendants discovered from the provider's on-disk transcripts.
    package var subagents: [SubagentStatus] = []
    /// The lead's plan and durable worker reports, including completed work.
    package var coordination: LeadCoordination? = nil

    /// The ones still working. A finished agent has nothing left to watch, so the lead's
    /// lists drop it; its transcript stays reachable from the task it was dispatched for.
    package var activeSubagents: [SubagentStatus] { subagents.filter(\.running) }

    /// Explicit, rather than the synthesized memberwise init, because `id` needs to be
    /// settable: the caller has to hand in the same UUID it passed Claude Code as
    /// `--session-id`, so this row's id is the key that finds that session's transcript.
    package init(
        id: UUID = UUID(), title: String, icon: String, line: String, agent: AgentKind? = nil,
        taskIDs: [String] = [], exited: Bool = false, subagents: [SubagentStatus] = [],
        coordination: LeadCoordination? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.line = line
        self.agent = agent
        self.taskIDs = taskIDs
        self.exited = exited
        self.subagents = subagents
        self.coordination = coordination
    }
}

extension CodeSession {
    package var isEngineeringLead: Bool { title.hasPrefix("Engineering Lead") }
}
