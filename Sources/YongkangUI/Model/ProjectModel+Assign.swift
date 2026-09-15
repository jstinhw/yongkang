import Foundation
import YongkangCore

extension ProjectModel {
    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// list and the board cannot disagree about what a batch is. Also the one place that
    /// excludes work a still-open lead session already has, so a task never goes to two
    /// leads at once.
    ///
    /// A lead that is still running is talked to, not duplicated: the new batch is typed
    /// into its own terminal as a follow-up message, the same as telling a person who is
    /// already working "also pick these up" rather than hiring a second lead.
    ///
    /// Nil when there is nothing left to assign: every task is already done, or already has
    /// a lead on it.
    func assign(_ tasks: [NotebookCard], agent: AgentKind) -> Destination? {
        let batch = NotebookIndex.withBlockers(tasks, in: snapshot.cards, excluding: assignedTaskIDs)
        guard !batch.isEmpty else { return nil }
        if let lead = sessions.first(where: { $0.isEngineeringLead && !$0.exited }) {
            appendTaskIDs(batch.map(\.id), to: lead.id)
            return Destination(
                section: .agents, route: .session(lead.id),
                input: NotebookFormat.additionalTasksPrompt(
                    tasks: batch, sessionID: lead.id, agent: lead.agent ?? .claude))
        }
        // The id is minted here so the prompt can carry it: a lead that knows its own
        // session id can write it into any block it raises, and the answer comes back here.
        let id = UUID()
        return Destination(
            section: .agents,
            route: addSession(
                agent, id: id,
                prompt: NotebookFormat.engineeringPrompt(tasks: batch, sessionID: id, agent: agent),
                title: "Engineering Lead", taskIDs: batch.map(\.id)))
    }
}
