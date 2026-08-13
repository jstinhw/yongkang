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

struct CodeSession: Identifiable, Equatable {
    let id = UUID()
    let agent: AgentKind
    let title: String
    /// Passed to the agent as its opening prompt when the session starts.
    let prompt: String?
}
