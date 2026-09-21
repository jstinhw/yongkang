import Foundation

/// One agent as the sidebar lists it under its project, and as that project's Agents page
/// draws it. Usually a live session; when no session is left to stand behind it, what one left
/// waiting on you — a proposal, a block, or work nobody has approved yet.
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
            let block = blocks.waitingOnUser.first { block in
                !block.isProposal
                    && (block.session == session.id
                        || (block.session == nil && block.task.map(session.taskIDs.contains) == true))
            }
            let waiting = summary.waiting(for: session)
            // Held up on one task, the row is about that task, not whichever is first in its chain.
            let task = block?.task ?? current(of: session, in: summary)
            let title =
                task.flatMap { id in summary.tasks.first { $0.id == id }?.title ?? cards.first { $0.id == id }?.title }
                ?? session.title
            let state: AgentRow.State
            var reason: String?
            if !session.exited, let question = asking[session.id] {
                (state, reason) = (.needsYou, question)
            } else if let block {
                (state, reason) = (.needsYou, block.isDemo ? "demo ready to approve" : block.title)
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
        // Everything else waiting on you gets a row of its own: proposals, which hold up the
        // notebook rather than a task, a second block from a session already listed for its first,
        // and blocks whose session has gone. Each opens on itself, and says whose it is.
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

    /// The task a session is on now: the first of its chain not yet done, or the last one once
    /// every one is.
    private func current(of session: CodeSession, in summary: ChangeSummary) -> String? {
        session.taskIDs.first { id in summary.tasks.first { $0.id == id }?.done != true } ?? session.taskIDs.last
    }
}
