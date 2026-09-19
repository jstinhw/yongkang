import Foundation

/// One subagent an agent session has spawned, read off its own transcript on disk —
/// Claude Code's `subagents/` folder or Codex's rollout tree, whichever this session is.
package struct SubagentStatus: Identifiable, Equatable, Sendable {
    package let id: String
    package let description: String
    package let agentType: String
    package let running: Bool
    package let transcriptURL: URL
    /// The task this subagent was dispatched for, matched off its own label. Nil when the
    /// label names no task in the batch — a compaction or review subagent, or a session that
    /// ignored the naming rule.
    package var taskID: String? = nil
    /// The roster name of the team member whose skill this subagent runs, filled in when
    /// the session is read. Nil when the label names nobody on the team — a compaction or
    /// review agent, or a skill no team member owns.
    package var member: String? = nil

    package init(
        id: String,
        description: String,
        agentType: String,
        running: Bool,
        transcriptURL: URL,
        taskID: String? = nil,
        member: String? = nil
    ) {
        self.id = id
        self.description = description
        self.agentType = agentType
        self.running = running
        self.transcriptURL = transcriptURL
        self.taskID = taskID
        self.member = member
    }

    /// What to call it on screen: the person on the team, else the skill it runs.
    package var displayName: String { member ?? agentType }

    /// The same subagent, told who on the team it is. Neither provider can do this: the
    /// roster is the project's, and a CLI knows only the label it was spawned under.
    ///
    /// The skill comes back with the name, and replaces whatever the provider called this
    /// thread — Codex nicknames a spawned thread ("Dewey", "Dirac"), and a nickname colours
    /// no tile, groups under nobody, and outlives the run in the ledger.
    package func named(in team: [TeamMember]) -> SubagentStatus {
        guard let found = Team.running("\(description) \(agentType)", in: team) else { return self }
        return SubagentStatus(
            id: id, description: description, agentType: found.skill,
            running: running, transcriptURL: transcriptURL, taskID: taskID,
            member: found.member.name)
    }
}

/// The subagents attached to one assigned task, including an empty group while that task
/// waits for a dependency or for its session to get to it.
struct SubagentTaskGroup: Identifiable {
    let id: String
    let subagents: [SubagentStatus]
}

/// One human-readable line pulled out of a subagent's transcript: the task it was given,
/// each tool it called, that tool's result, and its replies. Everything else in the file —
/// thinking blocks, bookkeeping fields — is left out rather than guessed at.
package struct TranscriptLine: Identifiable, Sendable {
    package let id = UUID()
    package let label: String
    package let text: String
    /// Set on a tool result the provider marked as failed — the one thing a collapsed run
    /// of work still has to be able to say out loud.
    package var isError = false

    package init(label: String, text: String, isError: Bool = false) {
        self.label = label
        self.text = text
        self.isError = isError
    }

}

/// What both providers share: neither CLI records which notebook task a subagent is for,
/// so the link is the subagent's own label. The work prompt asks for the task id in
/// every name a session spawns; Claude keeps that as the Agent call's `description`, Codex slugs
/// it into `agent_path`, and normalizing both to the same shape matches them either way.
enum Subagents {
    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// Longest id first, so a label naming `edit-todo-api` is not claimed by `edit-todo`.
    static func taskID(in label: String, from taskIDs: [String]) -> String? {
        let haystack = normalize(label)
        return taskIDs.sorted { $0.count > $1.count }.first { haystack.contains(normalize($0)) }
    }

    static func grouped(_ subagents: [SubagentStatus], by taskIDs: [String]) -> [SubagentTaskGroup] {
        taskIDs.map { taskID in
            SubagentTaskGroup(id: taskID, subagents: subagents.filter { $0.taskID == taskID })
        }
    }

    static func runningTaskIDs(_ subagents: [SubagentStatus]) -> Set<String> {
        Set(subagents.compactMap { $0.running ? $0.taskID : nil })
    }
}
