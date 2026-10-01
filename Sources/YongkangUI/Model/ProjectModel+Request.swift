import Foundation
import YongkangCore

/// A request typed on the board, as it went to Product.
struct BoardRequest: Equatable {
    let session: UUID
    /// Every card on the board when it was sent. Whatever Product files is what is not in here.
    let before: Set<String>
}

extension ProjectModel {
    /// Hands what was typed in the board's request box to Product, which files it straight onto
    /// the board as milestones and tasks and decides what waits on what. Tags naming other
    /// projects go as paths the agent can open, and their folders are let in.
    ///
    /// The board stays on screen: the answer is the cards that turn up, so this goes nowhere.
    /// The `Destination` only carries what to type into a Product session already running —
    /// as a follow-up to the request it is on, or as a new request to one doing something else.
    func sendRequest(_ text: String, projects: [Mention.Project], agent: AgentKind) -> Destination {
        let (prompt, folders) = Mention.resolved(text, root: directory, projects: projects)
        let followUp = requestSession
        let sent =
            followUp.map { Destination(section: .board, route: .session($0.id), input: prompt) }
            ?? startProduct("describe\n" + prompt, agent: agent, reading: folders)
        if case .session(let id, _)? = sent.route, followUp == nil {
            request = BoardRequest(session: id, before: Set(cards.map(\.id)))
        }
        requestDraft = ""
        requestOpen = false
        return sent
    }

    /// The milestones and tasks Product has filed for the last request so far.
    var filed: [NotebookCard] {
        guard let request else { return [] }
        return cards.filter { ($0.kind == .project || $0.kind == .task) && !request.before.contains($0.id) }
    }

    /// The box answers a request Product is still on, rather than starting a new one.
    var requestFollowsUp: Bool { requestSession != nil }

    /// The Product session the last request went to, while it is still running.
    private var requestSession: CodeSession? {
        request.flatMap { request in sessions.first { $0.id == request.session && !$0.exited } }
    }
}
