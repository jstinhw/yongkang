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
    /// first one is already rewriting, so a running one is talked to instead. `reading` lets a
    /// new one into other projects' folders; a running one keeps the folders it started with.
    func startProduct(_ arguments: String, agent: AgentKind, reading: [URL] = []) -> Destination {
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
                title: "Product", reading: reading))
    }

    /// The session an empty project starts with. It drafts its plan into Blocks under its
    /// own id, so `Create project` on that draft comes back to this conversation.
    func startNotebookSetup(_ description: String, agent: AgentKind) -> Route {
        let id = UUID()
        return addSession(
            agent, id: id, prompt: NotebookFormat.onboardingPrompt(description: description, sessionID: id),
            title: "Notebook Setup")
    }

    /// The setup sessions whose job is over: the plan each drafted is done, and the agent has
    /// said what it wrote. Nothing is left for one to do — the board holds its work, and
    /// Product takes the next plan — so an open one would only sit in the sidebar.
    ///
    /// The prompt has the draft marked done as the last write, so what the transcript adds is
    /// only the wait for the closing summary.
    /// ponytail: a CLI with no transcript to read (Agy) ends on the draft alone and may lose
    /// that summary mid-line. Read its screen for an idle prompt if that one ever matters.
    func finishedSetups() async -> [CodeSession] {
        var finished: [CodeSession] = []
        for session in sessions where session.isNotebookSetup && !session.exited {
            guard let provider = session.agent?.provider,
                snapshot.blocks.contains(where: { $0.isProposal && $0.session == session.id && !$0.waiting })
            else { continue }
            if let url = await provider.transcriptURL(session: session.id, project: directory) {
                let lines = await reader.transcript(of: provider, at: url)
                guard AgentState.of(lines: lines, exited: false) == .waiting else { continue }
            }
            finished.append(session)
        }
        return finished
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
    /// "Product 2" too: a second Product session is numbered like any other. A session holding
    /// tasks is never Product, whatever its task happens to be called.
    var isProduct: Bool { taskIDs.isEmpty && (title == "Product" || title.hasPrefix("Product ")) }

    var isNotebookSetup: Bool {
        taskIDs.isEmpty && (title == "Notebook Setup" || title.hasPrefix("Notebook Setup "))
    }
}
