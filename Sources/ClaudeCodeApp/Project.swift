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

struct CodeSession: Identifiable, Equatable {
    let id = UUID()
    let agent: AgentKind
    let title: String
    /// Passed to the agent as its opening prompt when the session starts.
    let prompt: String?
}
