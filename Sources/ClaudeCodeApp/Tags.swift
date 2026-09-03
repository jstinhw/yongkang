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

    /// Every agent session has these two: its own transcript, and — for an Engineering
    /// Lead — the lanes of specialists it dispatched.
    static func transcript(_ id: UUID) -> String { "transcript:\(id.uuidString)" }
    static func lanes(_ id: UUID) -> String { "lanes:\(id.uuidString)" }
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

/// The ways to watch one agent session, and the selection tag each one is.
///
/// `transcript` is first because it is the default, for every session and not just the
/// lead: an agent's own transcript is what it has said and done, read as steps rather
/// than as a wall of terminal output that scrolls away. The lanes belong to a lead, which
/// is the only session with specialists under it; the terminal is for typing at any of
/// them, a click away rather than the thing you land on.
enum AgentPane: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case lanes = "Agents"
    case session = "Session"

    var id: Self { self }

    func tag(_ session: UUID) -> String {
        switch self {
        case .transcript: return Tag.transcript(session)
        case .lanes: return Tag.lanes(session)
        // The terminal is mounted under the plain session tag, so switching to it is the
        // same selection a terminal row makes.
        case .session: return session.uuidString
        }
    }

    /// The panes a session actually has. Only a lead dispatches specialists, so only a
    /// lead has lanes to show them in.
    static func cases(lead: Bool) -> [AgentPane] {
        lead ? allCases : allCases.filter { $0 != .lanes }
    }

    /// Which pane a selection is showing for this session, or nil when it points elsewhere.
    static func of(_ selection: String?, session: UUID) -> AgentPane? {
        allCases.first { $0.tag(session) == selection }
    }
}
