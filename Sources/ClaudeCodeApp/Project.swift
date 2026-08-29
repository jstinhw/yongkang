import Foundation

/// A project is a folder. Its agents run there, its notebook lives in `.notebook/`
/// inside it, and both are only ever reachable through the project.
struct Project: Identifiable, Equatable {
    let id = UUID()
    let directory: URL
    var entries: [NotebookEntry] = []
    /// Frontmatter for the board, read only while you are inside the project.
    var cards: [NotebookCard] = []
    /// What the agents need from the user before they can go on, read the same way.
    var blocks: [UserBlock] = []
    var sessions: [CodeSession] = []

    var name: String { directory.lastPathComponent }
    var notebookRoot: URL { NotebookFormat.root(in: directory) }
    /// No `.notebook` on disk means no entries — the folder is left untouched.
    var hasNotebook: Bool { !entries.isEmpty }
    var pageCount: Int { NotebookLoader.pageCount(entries) }
    /// Tasks an open session already has. The WIP set: assigning again while a lead is
    /// still on a task would just hand it to a second one.
    var assignedTaskIDs: Set<String> { Set(sessions.flatMap(\.taskIDs)) }
}

/// The open project list, as it survives a relaunch. Paths, not bookmarks: the app is
/// not sandboxed, so a path is enough to reopen a folder the user already picked.
enum OpenProjects {
    static func encode(_ paths: [String]) -> String {
        guard let data = try? JSONEncoder().encode(paths) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func decode(_ text: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }
}

/// A terminal in the sidebar. It holds the shell line rather than an agent, because a
/// running service is the same thing to the window: a PTY in a directory.
struct CodeSession: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String
    let line: String
    /// Tasks this session was handed, in the order it was given them. Empty for anything
    /// that is not an Engineering Lead — a plain session was not assigned work.
    var taskIDs: [String] = []
    /// Set once the underlying process exits — a dead session is never routed more work.
    var exited: Bool = false
    /// Subagents this session has spawned, read off its own Claude Code transcript on
    /// disk. Always empty for Codex and service-runner sessions — they never get a
    /// matching `--session-id`, so there is nothing on disk to find.
    var subagents: [SubagentStatus] = []

    /// Explicit, rather than the synthesized memberwise init, because `id` needs to be
    /// settable: the caller has to hand in the same UUID it passed Claude Code as
    /// `--session-id`, so this row's id is the key that finds that session's transcript.
    init(id: UUID = UUID(), title: String, icon: String, line: String,
         taskIDs: [String] = [], exited: Bool = false, subagents: [SubagentStatus] = []) {
        self.id = id
        self.title = title
        self.icon = icon
        self.line = line
        self.taskIDs = taskIDs
        self.exited = exited
        self.subagents = subagents
    }
}
