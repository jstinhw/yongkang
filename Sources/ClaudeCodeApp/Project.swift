import Foundation

/// A project is a folder. Its agents run there, its notebook lives in `.notebook/`
/// inside it, and both are only ever reachable through the project.
struct Project: Identifiable, Equatable {
    let id = UUID()
    let directory: URL
    var entries: [NotebookEntry] = []
    /// Frontmatter for the board, read only while you are inside the project.
    var cards: [NotebookCard] = []
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
    let id = UUID()
    let title: String
    let icon: String
    let line: String
    /// Tasks this session was handed, in the order it was given them. Empty for anything
    /// that is not an Engineering Lead — a plain session was not assigned work.
    var taskIDs: [String] = []
}
