import Foundation

/// What the window has selected: the row the list column highlights and the page the work
/// area shows. It lives here rather than in the window so the list column and the work area
/// cannot disagree about what a selection means.
///
/// Selection has to survive the 2-second reload that replaces the model wholesale when an
/// agent writes a file, so every case carries only an ID that reload keeps: a card id, a
/// session UUID, a file path, a roster name. None carries the project's own id, because a
/// selection only ever means something inside the entered project, and entering one resets it.
package enum Route: Hashable, Sendable {
    case overview, board
    /// The project-wide usage screen, which belongs to no single agent.
    case usage

    /// Notebook pages on the board, by card id. Projects and tasks have screens of their
    /// own; `page` is every other kind.
    case project(String)
    case task(String)
    case page(String)
    /// A notebook file in the editor, by `NotebookEntry.id`.
    case entry(String)

    /// An agent session on one of its panes. The terminal is the default: a service runner
    /// has no other pane, and switching a lead to its terminal is the same selection a
    /// terminal row makes.
    case session(UUID, pane: AgentPane = .session)
    /// A subagent by its provider's id, which is only unique inside the session that spawned it.
    case subagent(session: UUID, id: String)
    /// A block by its file path, the same stable id `NotebookEntry` uses.
    case block(String)
    /// A standing team member, by roster name. Not a session — nothing is running — so it
    /// keys on the name rather than a UUID.
    case member(String)

    /// The working tree under review, on one file or on none picked yet.
    case review(file: String?)
    /// One task's review page.
    case reviewTask(String)
    /// One repo's preview, by its directory.
    case preview(URL)

    /// The card id out of a notebook page, whichever kind of page it is.
    package var cardID: String? {
        switch self {
        case .project(let id), .task(let id), .page(let id): return id
        default: return nil
        }
    }

    /// The card this route points at, when it is a notebook page.
    package func card(in cards: [NotebookCard]) -> NotebookCard? {
        cardID.flatMap { id in cards.first { $0.id == id } }
    }

    /// Which pane of this session the route is showing, or nil when it points elsewhere.
    package func pane(of session: UUID) -> AgentPane? {
        guard case .session(session, let pane) = self else { return nil }
        return pane
    }
}

/// The available agent panes. Transcript remains implemented but is hidden for now.
package enum AgentPane: String, CaseIterable, Identifiable, Sendable {
    case transcript = "Transcript"
    case lanes = "Agents"
    case session = "Session"

    package var id: Self { self }

    /// The panes a session actually has. Only a lead dispatches specialists, so only a
    /// lead has lanes to show them in.
    package static func cases(lead: Bool) -> [AgentPane] {
        lead ? [.lanes, .session] : [.session]
    }
}
