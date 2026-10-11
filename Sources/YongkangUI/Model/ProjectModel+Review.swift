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
        guard let draft = reviewDrafts[task.id], !draft.isEmpty,
            let sent = send(draft.message(taskID: task.id, title: task.title), about: task, agent: agent)
        else { return nil }
        reviewDrafts[task.id] = nil
        return sent
    }

    /// One of the agent's review questions, answered: sent where a change request goes, and
    /// remembered so the review says what was sent until the agent rewrites its record. What the
    /// user has drafted for the task stays — an answer is not the review's end.
    func answer(_ question: String, with answer: String, on task: SummaryTask, agent: AgentKind) -> Destination? {
        let message = """
            On \(task.id) — "\(task.title)" — you asked: \(question)
            My answer: \(answer)
            Act on it: set the task active while you do, and done again once its Done when holds.
            Rewrite the task's run record and its Review, and do not commit.
            """
        guard let sent = send(message, about: task, agent: agent) else { return nil }
        answers[Self.answerKey(question, on: task.id)] = answer
        return sent
    }

    /// What was sent for one question, or nil before anything was.
    func answered(_ question: String, on taskID: String) -> String? {
        answers[Self.answerKey(question, on: taskID)]
    }

    private static func answerKey(_ question: String, on taskID: String) -> String { taskID + "\n" + question }

    /// A task the user can throw away from the board: finished and waiting for review, or
    /// stopped on a demo or a gate. Nil when there is neither work nor a block to discard.
    func discardable(_ id: String) -> SummaryTask? {
        guard let task = summary.tasks.first(where: { $0.id == id }) else { return nil }
        let held = cards.first { $0.id == id }?.status == "blocked"
        return (task.done && !task.discardPaths.isEmpty) || held ? task : nil
    }

    /// Discarding is approving's opposite: this task's code and its records go back to the last
    /// commit, a demo or a gate still open on it is settled, and the task goes back to `todo`
    /// for the board to assign again. No agent starts.
    func discard(_ task: SummaryTask) async throws(CommitFailure) {
        let changes = repo.changes.filter { task.discardPaths.contains($0.path) }
        // A task stopped on a block may have left nothing in the tree yet.
        if !changes.isEmpty {
            let failure = await GitClient.discard(changes, in: directory)
            await refreshRepo()
            if let failure { throw CommitFailure(reason: failure) }
        }
        reviewDrafts[task.id] = nil
        // Left open, a block would hold the task at `blocked` over the `todo` below.
        snapshot.blocks.waitingOnUser.filter { !$0.isProposal && $0.task == task.id }.forEach(Blocks.resolve)
        do {
            try task.url.map(NotebookFormat.reopen)
        } catch {
            throw CommitFailure(
                reason: "The work is gone, but \(task.id) could not be set back to todo: "
                    + error.localizedDescription)
        }
    }

    private func send(_ message: String, about task: SummaryTask, agent: AgentKind) -> Destination? {
        if let holder = sessions.first(where: { $0.taskIDs.contains(task.id) && !$0.exited }) {
            return Destination(section: .agents, route: .session(holder.id), input: message)
        }
        guard let card = snapshot.cards.first(where: { $0.id == task.id }) else { return nil }
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
