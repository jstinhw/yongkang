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

    /// Whether this is a running session's own row, which is all the Agents tab lists. The
    /// others — a proposal, a block or a review no running session stands behind — still count
    /// on the project, and wait on the board.
    package var isRunningSession: Bool {
        guard let session, !session.exited else { return false }
        return id == session.id.uuidString
    }
}

extension Project {
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
            let block = question == nil ? raised : nil
            let waiting = summary.waiting(for: session)
            // Held up on one task, the row is about that task, not whichever is first in its chain.
            let task = block?.task ?? current(of: session, in: summary)
            let title =
                task.flatMap { id in summary.tasks.first { $0.id == id }?.title ?? cards.first { $0.id == id }?.title }
                ?? session.title
            let state: AgentRow.State
            var reason: String?
            if let question {
                (state, reason) = (.needsYou, question)
            } else if let block {
                (state, reason) = (
                    .needsYou,
                    block.isProposal ? "wants your opinion" : block.isDemo ? "demo ready to approve" : block.title
                )
            } else if !waiting.isEmpty {
                state = .review
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
            // A session waiting on you for one thing may have finished another: its row says the
            // first, so the finished work gets a review row of its own below rather than hiding.
            let reviewed = state == .review ? [] : Set(waiting.map(\.id))
            claimedTasks.formUnion(session.taskIDs.filter { !reviewed.contains($0) })
            rows.append(
                AgentRow(
                    id: session.id.uuidString, state: state, title: title, reason: reason,
                    session: session, task: task, block: block, route: route))
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
            let block = blocks.waiting(on: task.id)
            let state: AgentRow.State
            let route: Route
            if let block {
                (state, route) = (.needsYou, .block(block.id))
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
                block: block, route: route)
        }
        return rows.enumerated().sorted { ($0.element.state, $0.offset) < ($1.element.state, $1.offset) }.map(\.element)
    }

    /// The task a session is on now: the first of its chain not yet done, or the last one once
    /// every one is.
    private func current(of session: CodeSession, in summary: ChangeSummary) -> String? {
        session.taskIDs.first { id in summary.tasks.first { $0.id == id }?.done != true } ?? session.taskIDs.last
    }
}
