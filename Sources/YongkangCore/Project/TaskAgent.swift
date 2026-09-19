import Foundation

/// An agent on a task: the session assigned it, or a subagent that session dispatched for
/// it. One session per chain of work means the session is usually the one doing it, so a
/// screen that only listed subagents would show nobody on a task an agent is working on
/// right now.
package struct TaskAgent: Identifiable, Equatable, Sendable {
    package let session: CodeSession
    /// Nil when the session is working the task itself.
    package let subagent: SubagentStatus?

    package init(session: CodeSession, subagent: SubagentStatus? = nil) {
        self.session = session
        self.subagent = subagent
    }

    /// Scoped to the session: a provider's agent id is only unique inside the one that
    /// spawned it, so two sessions can hold the same one.
    package var id: String { "\(session.id.uuidString)-\(subagent?.id ?? "")" }
    package var title: String { subagent?.displayName ?? session.title }
    /// What the tile draws. A session doing its own work has no skill to name.
    package var role: String { subagent?.agentType ?? "work" }
    package var running: Bool { subagent.map(\.running) ?? !session.exited }
    /// Where clicking it goes: the subagent's live child view, or the session itself.
    package var route: Route {
        subagent.map { .subagent(session: session.id, id: $0.id) } ?? .session(session.id)
    }
    /// The task it is on. A session holding a chain is shown against the first of them.
    // ponytail: the first task, not the one it is on this minute — that is in its reports,
    // which this is drawn beside rather than from.
    package var taskID: String? { subagent?.taskID ?? session.taskIDs.first }
}

extension Project {
    /// Everyone on one task: the live sessions it was assigned to, each ahead of the
    /// subagents it dispatched for that task. An exited session is nobody working.
    package func agents(on taskID: String) -> [TaskAgent] {
        sessions.flatMap { session in
            (session.taskIDs.contains(taskID) && !session.exited ? [TaskAgent(session: session)] : [])
                + session.subagents.filter { $0.taskID == taskID }.map { TaskAgent(session: session, subagent: $0) }
        }
    }

    /// Everything working right now, whether it is a session on assigned work or a subagent
    /// one of them started.
    package var runningAgents: [TaskAgent] {
        sessions.flatMap { session in
            (session.holdsTasks && !session.exited ? [TaskAgent(session: session)] : [])
                + session.activeSubagents.map { TaskAgent(session: session, subagent: $0) }
        }
    }
}
