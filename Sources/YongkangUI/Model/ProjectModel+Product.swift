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

    /// The session a project without a notebook starts with: from what the user typed, or, with
    /// no description, from reading the folder. It drafts its plan into Blocks under its own
    /// id, so `Create project` on that draft comes back to this conversation. It opens under
    /// Agents, wherever it was started from, since that is the list its row sits in.
    func startNotebookSetup(_ description: String?, agent: AgentKind) -> Destination {
        setupStarted = true
        let id = UUID()
        return Destination(
            section: .agents,
            route: addSession(
                agent, id: id, prompt: NotebookFormat.onboardingPrompt(description: description, sessionID: id),
                title: "Notebook Setup"))
    }

    /// The Notebook Setup still writing this notebook, if one is.
    var runningSetup: CodeSession? { sessions.first { $0.isNotebookSetup && !$0.exited } }

    /// Product has nothing to review or file a request into until the notebook is written:
    /// there is none yet, or Notebook Setup is still writing it.
    var awaitingNotebook: Bool { !hasNotebook || runningSetup != nil }

    /// Where the notebook's first write stands, for the board to show in place of a board. Nil
    /// when there is nothing to say: no setup is running and there is a notebook to draw, or a
    /// folder with nothing in it, which has the intake instead.
    ///
    /// The phase is read off what is on disk — the plan draft, then the first entries — so it is
    /// the same answer for any CLI. Waiting is separate because a question can come up in any
    /// phase: a trust prompt while reading, a permission prompt while writing.
    func notebookSetup(asking: [UUID: String]) -> NotebookSetup? {
        guard let session = runningSetup else {
            guard !hasNotebook, hasFiles else { return nil }
            return NotebookSetup(
                phase: .stopped, waiting: false, reviewsPlan: false, session: sessions.last { $0.isNotebookSetup },
                plan: nil)
        }
        let plan = plan(of: session)
        let phase: NotebookSetupCard.Phase =
            hasNotebook ? .writing : plan?.waiting == true ? .planReady : .reading
        // Its turn over with nothing written is a question in prose. With the plan open, the turn
        // is over because the plan is the question; once its work is on disk, it is signing off.
        let quiet = session.idle && phase != .planReady && !wroteNotebook(plan: plan)
        return NotebookSetup(
            phase: phase, waiting: asking[session.id] != nil || quiet,
            // An import reads code into a roadmap with nothing to approve; a described project,
            // which an empty folder is, drafts a plan first.
            reviewsPlan: plan != nil || !hasFiles, session: session, plan: plan)
    }

    private func plan(of session: CodeSession) -> UserBlock? {
        snapshot.blocks.first { $0.isProposal && $0.session == session.id }
    }

    /// A setup's work is on disk: a described project's plan marked done, or an import's roadmap.
    private func wroteNotebook(plan: UserBlock?) -> Bool {
        plan.map { !$0.waiting } ?? hasNotebook
    }

    /// What the setup session last did, read off its transcript. Nil for a CLI that keeps none.
    func activity(of session: CodeSession?) async -> AgentActivity? {
        guard let session, !session.exited, let provider = session.agent?.provider,
            let url = await provider.transcriptURL(session: session.id, project: directory)
        else { return nil }
        return AgentActivity(lines: await reader.transcript(of: provider, at: url), in: directory)
    }

    /// The setup sessions whose job is over: its work is on disk — a described project's plan
    /// marked done, an import's roadmap written — and the agent has said what it wrote. Nothing
    /// is left for one to do — the board holds its work, and Product takes the next plan — so an
    /// open one would only sit in the sidebar.
    ///
    /// Each prompt makes that the last write, so what the transcript adds is only the wait for
    /// the closing summary.
    /// ponytail: a CLI with no transcript to read (Agy) ends on the write alone and may lose
    /// that summary mid-line. Read its screen for an idle prompt if that one ever matters.
    func finishedSetups() async -> [CodeSession] {
        var finished: [CodeSession] = []
        for session in sessions where session.isNotebookSetup && !session.exited {
            guard let provider = session.agent?.provider, wroteNotebook(plan: plan(of: session)) else { continue }
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

/// See `ProjectModel.notebookSetup`.
struct NotebookSetup {
    let phase: NotebookSetupCard.Phase
    /// A question is up in its session, or it has stopped to ask one.
    let waiting: Bool
    /// It drafts a plan for the user to approve before it writes: a described project, not an import.
    let reviewsPlan: Bool
    /// The session running it, or for `stopped` the last one still listed, if any.
    let session: CodeSession?
    let plan: UserBlock?
}

extension CodeSession {
    /// "Product 2" too: a second Product session is numbered like any other. A session holding
    /// tasks is never Product, whatever its task happens to be called.
    var isProduct: Bool { taskIDs.isEmpty && (title == "Product" || title.hasPrefix("Product ")) }

    var isNotebookSetup: Bool {
        taskIDs.isEmpty && (title == "Notebook Setup" || title.hasPrefix("Notebook Setup "))
    }
}
