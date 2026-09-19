import Foundation
import YongkangCore

/// git's reason a commit did not happen, shown under the button that asked for it.
struct CommitFailure: Error, Equatable {
    let reason: String
}

extension ProjectModel {
    /// Approving is committing: only this task's files and its records, then on to the
    /// next task waiting. Nothing is sent to the agent — it already marked the task done.
    func approve(_ task: SummaryTask, message: String) async throws(CommitFailure) -> Route {
        let failure = await GitClient.commit(message: message, paths: task.commitPaths, in: directory)
        await refreshRepo()
        if let failure { throw CommitFailure(reason: failure) }
        reviewDrafts[task.id] = nil
        return firstReview
    }

    /// Sending a task back goes to the session that holds it, typed into its terminal like
    /// any follow-up; with none running, a fresh one starts with the task and the comments.
    ///
    /// Nil when there is nothing written to send, or the task is no longer in the notebook.
    func requestChanges(on task: SummaryTask, agent: AgentKind) -> Destination? {
        guard let draft = reviewDrafts[task.id], !draft.isEmpty else { return nil }
        let message = draft.message(taskID: task.id, title: task.title)
        if let holder = sessions.first(where: { $0.taskIDs.contains(task.id) && !$0.exited }) {
            reviewDrafts[task.id] = nil
            return Destination(section: .agents, route: .session(holder.id), input: message)
        }
        guard let card = snapshot.cards.first(where: { $0.id == task.id }) else { return nil }
        reviewDrafts[task.id] = nil
        let id = UUID()
        return Destination(
            section: .agents,
            route: addSession(
                agent, id: id, prompt: NotebookFormat.workPrompt(tasks: [card], sessionID: id, message: message),
                title: card.title, taskIDs: [task.id]))
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
