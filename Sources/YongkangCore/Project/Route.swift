import Foundation

/// Every row in the app selects by a string tag, because selection has to survive the
/// 2-second reload that replaces the model wholesale when an agent writes a file. The
/// formats live here rather than in the window so the list column and the work area cannot
/// disagree about what a selection means.
package enum Tag {
    package static func overview(_ project: Project) -> String { "overview:\(project.id.uuidString)" }
    package static func board(_ project: Project) -> String { "board:\(project.id.uuidString)" }
    package static func review(_ project: Project) -> String { "review:\(project.id.uuidString)" }
    /// One task's review page. Its own prefix, not `review:`, whose suffix is a file path.
    package static func reviewTask(_ project: Project, _ taskID: String) -> String {
        "review-task:\(project.id.uuidString):\(taskID)"
    }
    /// The project-wide usage screen, which belongs to no single agent.
    package static func usage(_ project: Project) -> String { "usage:\(project.id.uuidString)" }

    package static func project(_ cardID: String) -> String { "project:\(cardID)" }
    package static func task(_ cardID: String) -> String { "task:\(cardID)" }
    package static func page(_ cardID: String) -> String { "page:\(cardID)" }

    /// Every agent session has these two: its own transcript, and — for an Engineering
    /// Lead — the lanes of specialists it dispatched.
    static func transcript(_ id: UUID) -> String { "transcript:\(id.uuidString)" }
    static func lanes(_ id: UUID) -> String { "lanes:\(id.uuidString)" }
    package static func session(_ session: CodeSession) -> String { session.id.uuidString }
    package static func subagent(_ session: CodeSession, _ subagent: SubagentStatus) -> String {
        "subagent:\(session.id.uuidString):\(subagent.id)"
    }
    package static func block(_ block: UserBlock) -> String { "block:\(block.id)" }
    /// A standing team member, by roster name. Not a session — nothing is running — so it
    /// keys on the name rather than a UUID, and survives the reload like every other tag.
    package static func member(_ name: String) -> String { "member:\(name)" }
    package static func preview(_ project: Project, _ directory: URL) -> String {
        "preview:\(project.id.uuidString):\(directory.path)"
    }

    /// The card id out of a `project:`/`task:`/`page:` tag, when the selection is one.
    package static func scope(_ selection: String?, _ prefix: String) -> String? {
        guard let selection, selection.hasPrefix(prefix + ":") else { return nil }
        return String(selection.dropFirst(prefix.count + 1))
    }

    /// The card a selection points at, whichever kind of page it is.
    package static func card(_ selection: String?, in cards: [NotebookCard]) -> NotebookCard? {
        for prefix in ["project", "task", "page"] {
            if let id = scope(selection, prefix) { return cards.first { $0.id == id } }
        }
        return nil
    }
}

/// The available agent panes. Transcript remains implemented but is hidden for now.
package enum AgentPane: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case lanes = "Agents"
    case session = "Session"

    package var id: Self { self }

    package func tag(_ session: UUID) -> String {
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
    package static func cases(lead: Bool) -> [AgentPane] {
        lead ? [.lanes, .session] : [.session]
    }

    /// Which pane a selection is showing for this session, or nil when it points elsewhere.
    package static func of(_ selection: String?, session: UUID) -> AgentPane? {
        allCases.first { $0.tag(session) == selection }
    }
}
