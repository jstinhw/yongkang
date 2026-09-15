import Foundation
import YongkangCore

/// git's reason a commit did not happen, shown under the button that asked for it.
struct CommitFailure: Error, Equatable {
    let reason: String
}

extension ProjectModel {
    /// Approving is committing: only this task's files and its records, then on to the
    /// next task waiting. Nothing is sent to the lead — it already marked the task done.
    func approve(_ task: SummaryTask, message: String) async throws(CommitFailure) -> Route {
        let failure = await GitClient.commit(message: message, paths: task.commitPaths, in: directory)
        await refreshRepo()
        if let failure { throw CommitFailure(reason: failure) }
        reviewDrafts[task.id] = nil
        return firstReview
    }

    /// Sending a task back goes to the lead that holds it, typed into its terminal like any
    /// follow-up; with no lead running, a fresh one starts with the task and the comments.
    ///
    /// Nil when there is nothing written to send, or the task is no longer in the notebook.
    func requestChanges(on task: SummaryTask, agent: AgentKind) -> Destination? {
        guard let draft = reviewDrafts[task.id], !draft.isEmpty else { return nil }
        let message = draft.message(taskID: task.id, title: task.title)
        let leads = sessions.filter { $0.isEngineeringLead && !$0.exited }
        if let lead = leads.first(where: { $0.taskIDs.contains(task.id) }) ?? leads.first {
            if !lead.taskIDs.contains(task.id) { appendTaskIDs([task.id], to: lead.id) }
            reviewDrafts[task.id] = nil
            return Destination(section: .agents, route: .session(lead.id), input: message)
        }
        guard let card = snapshot.cards.first(where: { $0.id == task.id }) else { return nil }
        reviewDrafts[task.id] = nil
        let id = UUID()
        return Destination(
            section: .agents,
            route: addSession(
                agent, id: id,
                prompt: NotebookFormat.changeRequestPrompt(task: card, message: message, sessionID: id, agent: agent),
                title: "Engineering Lead", taskIDs: [task.id]))
    }

    /// The review screen's one write to the repo. Staging and committing is all it does —
    /// no push, no merge, no branch — and only because the user pressed the button.
    func commit(_ message: String) async throws(CommitFailure) -> Route {
        let failure = await GitClient.commit(message: message, in: directory)
        await refreshRepo()
        if let failure { throw CommitFailure(reason: failure) }
        return .review(file: nil)
    }
}
