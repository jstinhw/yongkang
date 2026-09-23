import Foundation
import YongkangCore

/// git's reason a commit or a discard did not happen, shown to whoever asked for it.
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
        Analytics.capture("task_approved", ["files": task.commitPaths.count])
        reviewDrafts[task.id] = nil
        return firstReview
    }

    /// Sending a task back goes to the session that holds it, typed into its terminal like
    /// any follow-up; with none running, a fresh one starts with the task and the comments.
    ///
    /// Nil when there is nothing written to send, or the task is no longer in the notebook.
    func requestChanges(on task: SummaryTask, agent: AgentKind) -> Destination? {
        guard let draft = reviewDrafts[task.id], !draft.isEmpty else { return nil }
        return send(draft.message(taskID: task.id, title: task.title), about: task, agent: agent)
    }

    /// Discarding is approving's opposite: this task's code and its records go back to the last
    /// commit, and the task goes back to an agent the way a change request does, to start
    /// over. The task file is left alone — reopening it is the agent's, like every status.
    func discard(_ task: SummaryTask, agent: AgentKind) async throws(CommitFailure) -> Destination? {
        let failure = await GitClient.discard(
            repo.changes.filter { task.discardPaths.contains($0.path) }, in: directory)
        await refreshRepo()
        if let failure { throw CommitFailure(reason: failure) }
        reviewDrafts[task.id] = nil
        return send(
            "Discarded \(task.id) — \"\(task.title)\": its changes and its reports are gone. Set it back to "
                + "active, do it again from the start, check the Done when, and mark it done again. Do not commit.",
            about: task, agent: agent)
    }

    private func send(_ message: String, about task: SummaryTask, agent: AgentKind) -> Destination? {
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
                taskIDs: [task.id]))
    }

    /// The review screen's one write to the repo. Staging and committing is all it does —
    /// no push, no merge, no branch — and only because the user pressed the button.
    func commit(_ message: String) async throws(CommitFailure) -> Route {
        let failure = await GitClient.commit(message: message, in: directory)
        await refreshRepo()
        if let failure { throw CommitFailure(reason: failure) }
        Analytics.capture("changes_committed")
        return .review(file: nil)
    }
}
