import Foundation
import YongkangCore

extension ProjectModel {
    /// One session per chain of work, all on the agent picked beside the button: two tasks
    /// that wait on nothing start side by side in sessions of their own, and a task that
    /// waits on another in the same batch shares its session, because it cannot start while
    /// its blocker is still being written next door. Nothing is typed into a session already
    /// running — its agent may not be the one picked this time.
    ///
    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// list and the board cannot disagree about what a batch is. Also the one place that
    /// excludes work an open session already has, so a task never goes to two at once.
    ///
    /// The window goes to the first session started; the rest are in the Agents list beside
    /// it. Nil when there is nothing left to assign: every task is already done, or already
    /// has a session on it.
    func assign(_ tasks: [NotebookCard], agent: AgentKind) -> Destination? {
        let batch = NotebookIndex.withBlockers(tasks, in: snapshot.cards, excluding: assignedTaskIDs)
        guard !batch.isEmpty else { return nil }
        var opened: Route?
        for chain in NotebookIndex.chains(batch) {
            // The id is minted here so the prompt can carry it: a session that knows its own
            // id files its reports under it, and a block it raises finds its way back here.
            let id = UUID()
            let route = addSession(
                agent, id: id, prompt: NotebookFormat.workPrompt(tasks: chain, sessionID: id),
                title: title(of: chain), taskIDs: chain.map(\.id))
            if opened == nil { opened = route }
        }
        return Destination(section: .agents, route: opened)
    }

    /// A session is named after its work: the task, the project its chain belongs to, or how
    /// many tasks there are when one chain spans projects.
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
