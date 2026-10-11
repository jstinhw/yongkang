import Foundation
import YongkangCore

extension ProjectModel {
    /// "Do it now": the only way a gate reaches an agent. It goes to the one already on it, or
    /// is handed to one (`takeGate`). A proposal instead returns to its Product transcript, and
    /// only a ready proposal's create button sends approval.
    func startUnblock(_ block: UserBlock, agent: AgentKind) -> Destination {
        guard !block.isProposal else {
            return openProposal(block, approve: block.proposalReady, agent: agent)
        }
        if let running = value.holder(of: block) {
            return Destination(section: .agents, route: .session(running.id))
        }
        if let route = takeGate(block, agent: agent) {
            return Destination(section: .agents, route: route)
        }
        // The agent that filed it is still there: tell it to clear the gate, in its own session.
        let waiting = waitingSession(for: block)
        return Destination(
            section: .agents, route: waiting.map { .session($0.id) },
            input: NotebookFormat.unblockPrompt(block: block))
    }

    /// Hands `block` to the agent that filed it — one thread, one row, and it already knows
    /// what it was doing — or, when that agent is gone, opens a session for the gate alone.
    /// Nil when the prompt has to be typed into a session the caller owns the terminal for.
    ///
    /// Only ever on the user's click. Handing every new gate over unasked opened sessions
    /// nobody had started, the moment the file landed.
    func takeGate(_ block: UserBlock, agent: AgentKind) -> Route? {
        guidedBlocks.insert(block.id)
        guard waitingSession(for: block) == nil else { return nil }
        return addSession(
            agent, prompt: NotebookFormat.unblockPrompt(block: block), title: block.guideTitle)
    }

    /// The gates an agent is on, for the board — the same rule `Project.blocksForUser` applies
    /// to the sidebar, so the two columns cannot disagree about what is yours.
    var guidedBlockIDs: Set<String> {
        let project = value
        return Set(snapshot.blocks.waitingOnUser.filter { project.guide(of: $0) != nil }.map(\.id))
    }

    /// A proposal belongs to the Product conversation that shaped it. Opening it is only
    /// navigation; the ready proposal's explicit create action is the approval message.
    /// `agent` is only used when no Product session is left to return to.
    func openProposal(_ block: UserBlock, approve: Bool, agent: AgentKind) -> Destination {
        let running =
            block.session.flatMap { id in
                sessions.first { $0.id == id && !$0.exited }
            } ?? sessions.last { $0.isProduct && !$0.exited }
        if let running {
            return Destination(
                section: .agents, route: .session(running.id),
                input: approve
                    ? "Approved. Create the roadmap changes, project, and tasks in this ready proposal." : nil)
        }
        let decision = approve ? "\nDecision: approve" : ""
        return startProduct(NotebookFormat.relativePath(block.url) + decision, agent: agent)
    }

    /// Approving a demo is the one gesture that releases the engineering tasks waiting on
    /// a design task: the block is cleared the same way any other is, and the agent that
    /// made it is told which revision won. The app does not touch the task file — the
    /// agent owns that, like every other status in the notebook.
    func approveDemo(_ block: UserBlock, revision: DemoRevision?, agent: AgentKind) -> Destination? {
        Blocks.resolve(block)
        deliveredBlocks.insert(block.id)
        let pass = revision.map { " Build \($0.label)." } ?? ""
        return decision(
            on: block, agent: agent,
            "The demo at \(block.slug) is approved.\(pass) "
                + "Mark the design task done and start the tasks waiting on it.")
    }

    /// Saying what is wrong is the whole gesture: the user's own words, sent to whoever has
    /// the demo, and the demo stays open for the pass that answers them. Nothing is typed on
    /// their behalf, so nothing is sent until they have written something.
    ///
    /// Nil when they have not — the button says so rather than going quiet.
    func requestDemoChanges(_ block: UserBlock, note: String, agent: AgentKind) -> Destination? {
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        reviewDrafts[block.id] = nil
        return decision(on: block, agent: agent, NotebookFormat.demoChangeRequest(demo: block, note: note))
    }

    /// Where a demo's decision goes. A demo outlives the session that built it — it waits
    /// until the user has looked at it, which may be days and an app launch later — so
    /// neither answer may depend on that session still running. With it gone, the design
    /// task starts again carrying the decision, and the demo file tells the new agent where
    /// the last one got to. A gate cleared after its agent has gone goes the same way.
    ///
    /// Nil only when the demo names no task still in the notebook: there is nothing to
    /// reopen, and the block is already cleared.
    func decision(on block: UserBlock, agent: AgentKind, _ message: String) -> Destination? {
        if let waiting = waitingSession(for: block) {
            return Destination(section: .agents, route: .session(waiting.id), input: message)
        }
        guard let task = block.task.flatMap({ id in snapshot.cards.first { $0.id == id && $0.kind == .task } })
        else { return nil }
        let id = UUID()
        return Destination(
            section: .agents,
            route: addSession(
                agent, id: id,
                prompt: NotebookFormat.workPrompt(tasks: [task], sessionID: id, message: message),
                taskIDs: [task.id]))
    }
}
