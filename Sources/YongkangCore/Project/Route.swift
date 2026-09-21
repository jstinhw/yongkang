import Foundation

/// What the window has selected: the row the list column highlights and the page the work
/// area shows. It lives here rather than in the window so the list column and the work area
/// cannot disagree about what a selection means.
///
/// Selection has to survive the 2-second reload that replaces the model wholesale when an
/// agent writes a file, so every case carries only an ID that reload keeps: a card id, a
/// session UUID, a file path, a roster name. None carries the project's own id, because a
/// selection only ever means something inside the entered project, and entering one resets it.
package enum Route: Hashable, Sendable, Codable {
    case board
    /// The project-wide usage screen, which belongs to no single agent.
    case usage
    /// The project's agents side by side: what needs you, what waits for review, what is working.
    case agents
    /// What the project's agents decided and learned, on one memory entry or on the first.
    case memory(String?)

    /// Notebook pages on the board, by card id. Projects and tasks have screens of their
    /// own; `page` is every other kind.
    case project(String)
    case task(String)
    case page(String)
    /// A notebook file in the editor, by `NotebookEntry.id`.
    case entry(String)

    /// An agent session on one of its panes. The terminal is the default: a service runner
    /// has no other pane, and switching an assigned session to its terminal is the same selection a
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

    // MARK: - Storing one

    /// The route as one string, which is what `@SceneStorage` can keep: relaunching returns
    /// the window to the page it was on.
    ///
    /// Codable's own shape, deliberately not a format anything else reads or writes — so a
    /// string that no longer decodes is simply no route, the same answer as a route whose
    /// card an agent has since deleted. `RawRepresentable` would spell this too, but it also
    /// offers the stdlib's `==` through `rawValue`, and a selection is compared once per row
    /// per redraw: JSON in that path would be a real cost for no gain.
    package var stored: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    package init?(stored: String) {
        guard let decoded = try? JSONDecoder().decode(Route.self, from: Data(stored.utf8)) else { return nil }
        self = decoded
    }
}

/// The available agent panes. Transcript remains implemented but is hidden for now, so a
/// session shows its terminal; what it did is its tasks' reviews, each a row under it.
package enum AgentPane: String, Sendable, Codable {
    case transcript = "Transcript"
    case session = "Session"
}
