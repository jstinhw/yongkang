import Foundation
import YongkangCore

extension ProjectModel {
    /// One session per chain of work, all on the agent picked beside the button: two tasks
    /// that wait on nothing start side by side in sessions of their own, and a task that
    /// waits on another in the same batch shares its session, because it cannot start while
    /// its blocker is still being written next door. Nothing is typed into a session already
    /// running — its agent may not be the one picked this time.
    ///
    /// A session is named after the coding agent running it — "Claude Code", "Claude Code 2" —
    /// not its work: the Agents list shows its tasks under it by their own names.
    ///
    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// list and the board cannot disagree about what a batch is. Also the one place that
    /// excludes work an open session already has, so a task never goes to two at once.
    ///
    /// One session opens in the window. Several go to the board, whose chains list every
    /// one of them: opening the first would leave the rest in the Agents list, which the
    /// user may have hidden, and "Run 3 ready" would look like it ran one. Nil when there is
    /// nothing left to assign: every task is already done, or already has a session on it.
    func assign(_ tasks: [NotebookCard], agent: AgentKind) -> Destination? {
        let batch = NotebookIndex.withBlockers(tasks, in: snapshot.cards, excluding: assignedTaskIDs)
        guard !batch.isEmpty else { return nil }
        let routes = NotebookIndex.chains(batch).map { chain in
            // The id is minted here so the prompt can carry it: a session that knows its own
            // id files its reports under it, and a block it raises finds its way back here.
            let id = UUID()
            return addSession(
                agent, id: id, prompt: NotebookFormat.workPrompt(tasks: chain, sessionID: id),
                taskIDs: chain.map(\.id))
        }
        return routes.count == 1
            ? Destination(section: .agents, route: routes[0])
            : Destination(section: .board, route: .board)
    }
}
