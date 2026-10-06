import Foundation

/// One thing a project's agents have going: usually a live session, which the sidebar lists under
/// its project and the project's Agents page draws; when no session is left to stand behind it,
/// what one left waiting on you — a proposal, a block, or work nobody has approved yet — which
/// only counts there, and is opened from the board.
///
/// Derived, never stored. The sessions, the blocks and the review summary are the state; this is
/// only how they read side by side, so the sidebar and the page cannot disagree about a row.
package struct AgentRow: Identifiable, Equatable, Sendable {
    package enum State: Int, Comparable, Sendable {
        /// Only you can move it on: a question in its terminal, a block, a demo or a proposal.
        case needsYou
        /// Its work is done and waits, uncommitted, for your approval.
        case review
        case working

        package static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    package let id: String
    package let state: State
    /// What it is on, in the notebook's words: its task, or what it is asking you.
    package let title: String
    /// Why it is waiting on you, when it is: the question on its screen, or its block.
    package let reason: String?
    /// Nil for a row no live session stands behind.
    package let session: CodeSession?
    /// The task it is on, which names its milestone and holds its checklist.
    package let task: String?
    /// What it is waiting on you for, when that is a block: a gate, a demo or a proposal.
    package let block: UserBlock?
    /// Where clicking it goes.
    package let route: Route
    /// The other project its session is talking to, which its row and its header name.
    package var peer: Peer? = nil

    /// Whether this is a running session's own row, which is all the Agents tab lists. The
    /// others — a proposal, a block or a review no running session stands behind — still count
    /// on the project, and wait on the board.
    package var isRunningSession: Bool {
        guard let session, !session.exited else { return false }
        return id == session.id.uuidString
    }
}

/// Another open project a session is talking to, by its name: the one it wrote to and has not
/// heard back from, or the one whose message started it.
package enum Peer: Equatable, Sendable {
    case waitingOn(String)
    case askedBy(String)

    package var project: String {
        switch self {
        case .waitingOn(let name), .askedBy(let name): return name
        }
    }

    /// "waiting on", "asked by": what goes before the name.
    package var verb: String {
        switch self {
        case .waitingOn: return "waiting on"
        case .askedBy: return "asked by"
        }
    }
}

extension Project {
    /// The session waiting on this block — and, once the app has handed the gate back to it,
    /// the one working it through with the user. A block names its own session, so the answer
    /// reaches the one that asked even with several running; one written without a session id
    /// falls back to the newest live session holding the task it names, then any.
    package func waitingSession(for block: UserBlock) -> CodeSession? {
        // A proposal links to Product, but does not block an assigned session.
        guard !block.isProposal else { return nil }
        if let id = block.session {
            return sessions.first { $0.id == id && !$0.exited }
        }
        let live = sessions.filter { $0.holdsTasks && !$0.exited }
        return live.last { session in block.task.map { session.taskIDs.contains($0) } ?? false } ?? live.last
    }

    /// The agent working a gate through with the user right now: one the app has handed over
    /// this run, whose session is still alive to be doing it.
    ///
    /// It is the same agent that filed the gate, still on the task, rather than a second
    /// session beside it — which is what the user saw, two rows of the same name, one agent
    /// apparently twice. Only when that agent is gone is a session opened for the gate alone.
    package func guide(of block: UserBlock) -> CodeSession? {
        // Once it has stopped talking the gate is the user's again. A guide works a gate
        // through one step at a time, and its step is often a sentence rather than a prompt —
        // nothing on screen for the window to read as a question — so the end of its turn is
        // the only sign that it is the user's move. One guard here, because every screen that
        // asks who is on a gate asks through this.
        holder(of: block).flatMap { $0.idle ? nil : $0 }
    }

    /// The session a gate was handed to, whose it stays whether or not its turn is over.
    ///
    /// A session opened for the gate alone carries its name, which is how it is still the
    /// holder after a relaunch: `guided` is this run's memory and starts empty, while the
    /// session comes back (`OpenSessions`). Asking `guided` first was what opened a second
    /// agent of the same name on every launch.
    package func holder(of block: UserBlock) -> CodeSession? {
        if let opened = sessions.first(where: { !$0.exited && $0.title.hasPrefix(block.guideTitle) }) {
            return opened
        }
        guard guided.contains(block.id) else { return nil }
        return waitingSession(for: block)
    }

    /// The gate this session is working through, and so the page that belongs beside it.
    ///
    /// Not `guide(of:)`: whose move it is and which session the gate is in are different
    /// questions, and the pane needs the second. The user is on that page exactly while the
    /// agent waits for them — which is the moment `guide(of:)` hands the gate back, and the
    /// moment the page is most needed. Asking the first closed the pane on every step.
    package func gate(of session: CodeSession) -> UserBlock? {
        blocks.waitingOnUser.first { holder(of: $0)?.id == session.id }
    }

    /// Whether every task these ids name is finished in the notebook. A session whose chain is
    /// spent has nothing left to be open for: its work is over, and its reports stay in
    /// `runs/` whether or not it is still listed, so Review keeps them either way.
    ///
    /// Empty is not spent. A session handed no tasks — Product, a gate's guide, a service
    /// runner — is open for a reason its task list says nothing about.
    ///
    /// Read off the cards rather than the summary so a relaunch can ask before git has been
    /// read: `blocked` outranks `done` in `NotebookIndex.settled`, so a task still holding a
    /// gate open is never counted as finished here.
    package func isSpent(_ taskIDs: [String]) -> Bool {
        !taskIDs.isEmpty && taskIDs.allSatisfy { id in cards.first { $0.id == id }?.status == "done" }
    }

    /// What is actually on the user's desk: everything open in `blocks/`, less the gates an
    /// agent is already working through for them. A gate being worked is that agent's row —
    /// it reaches the user when the agent comes back with a question, which is one thing to
    /// answer rather than the whole procedure at once.
    package var blocksForUser: [UserBlock] {
        blocks.waitingOnUser.filter { guide(of: $0) == nil }
    }

    /// Every agent of this project worth a row: needs you first, then review, then working,
    /// each in the order the sessions were started. `asking` is each session's terminal question,
    /// which only the window can see.
    ///
    /// A session that has exited with nothing left waiting has no row: it is history, and its
    /// reports are on its tasks.
    package func agentRows(summary: ChangeSummary, asking: [UUID: String] = [:]) -> [AgentRow] {
        var rows: [AgentRow] = []
        var claimedBlocks: Set<String> = []
        var claimedTasks: Set<String> = []
        for session in sessions {
            // A proposal holds up the notebook rather than a task, so only the session that
            // wrote it waits on it.
            let raised = blocks.waitingOnUser.first { block in
                block.session == session.id
                    || (!block.isProposal && block.session == nil
                        && block.task.map(session.taskIDs.contains) == true)
            }
            // A question on its screen is what the row is about; a block beside it is counted
            // with a row of its own below.
            let question = session.exited ? nil : asking[session.id]
            // The gate this session is working through. It is not waiting on the user while
            // the agent is on it — the agent is the one moving it on — so the row stays
            // working until the agent itself asks something.
            let guiding = blocks.waitingOnUser.first { guide(of: $0)?.id == session.id }
            let block = question == nil ? (guiding ?? raised) : nil
            let waiting = summary.waiting(for: session)
            // The task it is on now: the first of its chain not yet done. None left means its
            // chain is spent, and the row keeps the last one's name rather than going anonymous.
            let unfinished = session.taskIDs.first { id in summary.tasks.first { $0.id == id }?.done != true }
            // Held up on one task, the row is about that task, not whichever is first in its chain.
            let task = block?.task ?? guiding?.task ?? unfinished ?? session.taskIDs.last
            let title =
                task.flatMap { id in summary.tasks.first { $0.id == id }?.title ?? cards.first { $0.id == id }?.title }
                ?? session.title
            let state: AgentRow.State
            var reason: String?
            if let question {
                (state, reason) = (.needsYou, question)
            } else if guiding != nil {
                state = .working
            } else if let block {
                (state, reason) = (
                    .needsYou,
                    block.isProposal ? "wants your opinion" : block.isDemo ? "demo ready to approve" : block.title
                )
            } else if !waiting.isEmpty {
                state = .review
            } else if case .waitingOn? = peers[session.id], !session.exited {
                // Its turn is over, but what comes next is the other project's answer, not yours.
                state = .working
            } else if session.idle, !session.exited {
                (state, reason) = (.needsYou, "It has finished and is waiting for your reply.")
            } else if !session.exited {
                state = .working
            } else {
                continue
            }
            // A live session opens on itself. A dead one has no terminal worth opening, so its
            // row goes to what it left: the block, or the first task waiting to be approved.
            let route: Route =
                session.exited
                ? (block.map { .block($0.id) } ?? waiting.first.map { .reviewTask($0.id) } ?? .session(session.id))
                : .session(session.id)
            if let block { claimedBlocks.insert(block.id) }
            // Claimed even when a question pushed it off this row: a gate someone is on must
            // not also appear below as something nobody has picked up.
            if let guiding { claimedBlocks.insert(guiding.id) }
            // A session waiting on you for one thing may have finished another: its row says the
            // first, so the finished work gets a review row of its own below rather than hiding.
            let reviewed = state == .review ? [] : Set(waiting.map(\.id))
            claimedTasks.formUnion(session.taskIDs.filter { !reviewed.contains($0) })
            rows.append(
                AgentRow(
                    id: session.id.uuidString, state: state, title: title, reason: reason,
                    session: session, task: task, block: block, route: route, peer: peers[session.id]))
        }
        // Everything else waiting on you gets a row of its own: a proposal no session wrote, a
        // second block from a session already listed for its first, and blocks whose session has
        // gone. Each opens on itself, and says whose it is.
        for block in blocks.waitingOnUser where !claimedBlocks.contains(block.id) {
            let reason = block.isProposal ? "wants your opinion" : block.isDemo ? "demo ready to approve" : "blocked"
            rows.append(
                AgentRow(
                    id: "block:\(block.id)", state: .needsYou, title: block.title, reason: reason,
                    session: sessions.first { $0.id == block.session }, task: block.task, block: block,
                    route: .block(block.id)))
        }
        // Finished work waiting for review that no row above stands for: a session's second
        // piece of news, or what a closed session left.
        for task in summary.waiting where !claimedTasks.contains(task.id) {
            rows.append(
                AgentRow(
                    id: "task:\(task.id)", state: .review, title: task.title, reason: nil,
                    session: sessions.first { !$0.exited && $0.taskIDs.contains(task.id) }, task: task.id,
                    block: nil, route: .reviewTask(task.id)))
        }
        // Stable, so each state keeps the order the sessions were started in.
        return rows.enumerated().sorted { ($0.element.state, $0.offset) < ($1.element.state, $1.offset) }.map(\.element)
    }

    /// Every task that is not idle, as the sidebar lists them under Board: held up on your
    /// approval, finished and waiting for your review, or out with a running session — the
    /// board's own states for a task, by the same rules, needs you first and in the board's order
    /// within each. A task that could start, or is waiting its turn, has no row.
    package func taskRows(summary: ChangeSummary) -> [AgentRow] {
        let waiting = summary.waitingIDs
        let assigned = assignedTaskIDs
        let rows = NotebookIndex.ordered(cards.filter { $0.kind == .task }).compactMap { task -> AgentRow? in
            let block = blocksForUser.waiting(on: task.id)
            // A gate a session is already clearing keeps its row — the task is neither idle nor
            // yours yet — but reads as work in progress rather than as something to answer.
            let guided = block == nil ? blocks.waiting(on: task.id) : nil
            let state: AgentRow.State
            let route: Route
            if let block {
                (state, route) = (.needsYou, .block(block.id))
            } else if let guided {
                (state, route) = (.working, .block(guided.id))
            } else if waiting.contains(task.id) {
                (state, route) = (.review, .reviewTask(task.id))
            } else if assigned.contains(task.id), task.status != "done" {
                (state, route) = (.working, .task(task.id))
            } else {
                return nil
            }
            return AgentRow(
                id: "task:\(task.id)", state: state, title: task.title, reason: block?.title,
                session: sessions.first { !$0.exited && $0.taskIDs.contains(task.id) }, task: task.id,
                block: block ?? guided, route: route)
        }
        return rows.enumerated().sorted { ($0.element.state, $0.offset) < ($1.element.state, $1.offset) }.map(\.element)
    }
}
