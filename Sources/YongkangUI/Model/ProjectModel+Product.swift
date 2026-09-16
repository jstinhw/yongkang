import Foundation
import YongkangCore

extension ProjectModel {
    /// Product looks at the whole product and discusses what should come next. Blocks gets
    /// one link back to that transcript, then the finalized plan; the board stays unchanged
    /// until the user explicitly creates it.
    func startProductReview(agent: AgentKind) -> Destination {
        startProduct("review", agent: agent)
    }

    /// One product voice per project. A second session would propose against a board the
    /// first one is already rewriting, so a running one is talked to instead — the same
    /// rule the Engineering Lead follows for a second batch.
    func startProduct(_ arguments: String, agent: AgentKind) -> Destination {
        if let running = sessions.first(where: { $0.isProduct && !$0.exited }) {
            return Destination(
                section: .agents, route: .session(running.id),
                input: NotebookFormat.productPrompt(
                    arguments: arguments, sessionID: running.id, agent: running.agent ?? .claude))
        }
        let id = UUID()
        return Destination(
            section: .agents,
            route: addSession(
                agent, id: id,
                prompt: NotebookFormat.productPrompt(arguments: arguments, sessionID: id, agent: agent),
                title: "Product"))
    }

    /// The session an empty project starts with. It drafts its plan into Blocks under its
    /// own id, so `Create project` on that draft comes back to this conversation.
    func startNotebookSetup(_ description: String, agent: AgentKind) -> Route {
        let id = UUID()
        return addSession(
            agent, id: id, prompt: NotebookFormat.onboardingPrompt(description: description, sessionID: id),
            title: "Notebook Setup")
    }

    /// Incubate mode: the app does not write the agent, a session does. It searches the
    /// skills this project can already load, fetches or writes what is missing, and adds
    /// the file to `.notebook/team/` — which the poll picks up as a new roster row, the
    /// same way any other notebook entry an agent writes turns up.
    func startIncubation(_ brief: String, agent: AgentKind) -> Destination {
        Destination(
            section: .agents,
            route: addSession(
                agent, prompt: NotebookFormat.incubatePrompt(brief: brief, agent: agent), title: "New Agent"))
    }
}

extension CodeSession {
    /// "Product 2" too: a second Product session is numbered like a second lead.
    var isProduct: Bool { title == "Product" || title.hasPrefix("Product ") }
}
