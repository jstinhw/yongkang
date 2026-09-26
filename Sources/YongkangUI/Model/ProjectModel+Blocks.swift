import Foundation
import YongkangCore

extension ProjectModel {
    /// A gate starts a session whose only job is unblocking it — or goes to the one already
    /// on it, since the poll usually got there first. A proposal instead returns to its
    /// Product transcript, and only a ready proposal's create button sends approval.
    func startUnblock(_ block: UserBlock, agent: AgentKind) -> Destination {
        guard !block.isProposal else {
            return openProposal(block, approve: block.proposalReady, agent: agent)
        }
        if let running = value.guide(of: block) {
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

    /// Opens the session that clears a gate, unasked and without going to it. A block file is
    /// an agent's gate, not news: most of them turn out to need nothing from the user — a CLI
    /// already logged in, a repo that already exists — and the ones that do are better asked
    /// one step at a time than filed as a ten-step page. The window hears about it when the
    /// agent itself comes back with a question, like any other session.
    ///
    /// The next gate to hand to an agent, and who should take it — the session that filed it,
    /// still on the task, or nobody when that session has gone.
    ///
    /// Once per gate per run: a guide that gives up leaves the block waiting on the user again,
    /// which is the honest state, and starting another would be a loop. One at a time, too —
    /// two agents asking at once is two conversations nobody started, and opening a project
    /// whose `blocks/` has a year of open files in it would be a CLI per file.
    func nextGate() -> (block: UserBlock, session: CodeSession?)? {
        let open = snapshot.blocks.waitingOnUser
        // The common answer, on every tick of every project: nothing is blocked. Settled off
        // `blocks` alone, before building a whole `Project` value to ask the rest.
        guard let next = open.first(where: { $0.isGate && !guidedBlocks.contains($0.id) }) else { return nil }
        let project = value
        guard !open.contains(where: { project.guide(of: $0) != nil }) else { return nil }
        return (next, project.waitingSession(for: next))
    }

    /// Hands `block` to the agent that filed it — one thread, one row, and it already knows
    /// what it was doing — or, when that agent is gone, opens a session for the gate alone.
    /// Nil when the prompt has to be typed into a session the caller owns the terminal for.
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
    /// the last one got to.
    ///
    /// Nil only when the demo names no task still in the notebook: there is nothing to
    /// reopen, and the block is already cleared.
    private func decision(on block: UserBlock, agent: AgentKind, _ message: String) -> Destination? {
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
