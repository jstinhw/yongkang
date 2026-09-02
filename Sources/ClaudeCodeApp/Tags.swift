import Foundation

/// Every row in the app selects by a string tag, because selection has to survive the
/// 2-second reload that replaces the model wholesale when an agent writes a file. The
/// formats live here rather than in the window so the list column and the work area cannot
/// disagree about what a selection means.
enum Tag {
    static func overview(_ project: Project) -> String { "overview:\(project.id.uuidString)" }
    static func board(_ project: Project) -> String { "board:\(project.id.uuidString)" }
    static func review(_ project: Project) -> String { "review:\(project.id.uuidString)" }

    static func project(_ cardID: String) -> String { "project:\(cardID)" }
    static func task(_ cardID: String) -> String { "task:\(cardID)" }
    static func page(_ cardID: String) -> String { "page:\(cardID)" }

    static func lead(_ id: UUID) -> String { "lead:\(id.uuidString)" }
    static func session(_ session: CodeSession) -> String { session.id.uuidString }
    static func subagent(_ session: CodeSession, _ subagent: SubagentStatus) -> String {
        "subagent:\(session.id.uuidString):\(subagent.id)"
    }
    static func block(_ block: UserBlock) -> String { "block:\(block.id)" }
    static func preview(_ project: Project, _ directory: URL) -> String {
        "preview:\(project.id.uuidString):\(directory.path)"
    }

    /// The card id out of a `project:`/`task:`/`page:` tag, when the selection is one.
    static func scope(_ selection: String?, _ prefix: String) -> String? {
        guard let selection, selection.hasPrefix(prefix + ":") else { return nil }
        return String(selection.dropFirst(prefix.count + 1))
    }

    /// The card a selection points at, whichever kind of page it is.
    static func card(_ selection: String?, in cards: [NotebookCard]) -> NotebookCard? {
        for prefix in ["project", "task", "page"] {
            if let id = scope(selection, prefix) { return cards.first { $0.id == id } }
        }
        return nil
    }
}
