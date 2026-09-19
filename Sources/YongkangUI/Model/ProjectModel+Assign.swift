import Foundation
import YongkangCore

extension ProjectModel {
    /// Every assignment is a session of its own, on the agent picked beside the button: one
    /// task is one session, and a project or a picked batch is one session that splits the
    /// work among its own subagents. Nothing is typed into a session already running — its
    /// agent may not be the one picked this time.
    ///
    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// list and the board cannot disagree about what a batch is. Also the one place that
    /// excludes work an open session already has, so a task never goes to two at once.
    ///
    /// Nil when there is nothing left to assign: every task is already done, or already has
    /// a session on it.
    func assign(_ tasks: [NotebookCard], agent: AgentKind) -> Destination? {
        let batch = NotebookIndex.withBlockers(tasks, in: snapshot.cards, excluding: assignedTaskIDs)
        guard !batch.isEmpty else { return nil }
        // The id is minted here so the prompt can carry it: a session that knows its own id
        // files its reports under it, and a block it raises finds its way back here.
        let id = UUID()
        return Destination(
            section: .agents,
            route: addSession(
                agent, id: id, prompt: NotebookFormat.workPrompt(tasks: batch, sessionID: id),
                title: title(of: batch), taskIDs: batch.map(\.id)))
    }

    /// A session is named after its work: the task, the project its tasks all belong to, or
    /// how many there are when a batch spans projects.
    private func title(of batch: [NotebookCard]) -> String {
        if batch.count == 1, let only = batch.first { return only.title }
        let projects = Set(batch.map(\.project))
        if projects.count == 1, let id = projects.first ?? nil,
            let project = snapshot.cards.first(where: { $0.kind == .project && $0.id == id })
        {
            return project.title
        }
        return "\(batch.count) tasks"
    }
}
