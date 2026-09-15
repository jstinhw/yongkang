import Foundation

/// One subagent an agent session has spawned, read off its own transcript on disk —
/// Claude Code's `subagents/` folder or Codex's rollout tree, whichever this session is.
struct SubagentStatus: Identifiable, Equatable {
    let id: String
    let description: String
    let agentType: String
    let running: Bool
    let transcriptURL: URL
    /// The task this subagent was dispatched for, matched off its own label. Nil when the
    /// label names no task in the batch — a compaction or review subagent, or a lead that
    /// ignored the naming rule.
    var taskID: String? = nil
    /// The roster name of the team member whose skill this subagent runs, filled in when
    /// the session is read. Nil when the label names nobody on the team — a compaction or
    /// review agent, or a skill no team member owns.
    var member: String? = nil

    /// What to call it on screen: the person on the team, else the skill it runs.
    var displayName: String { member ?? agentType }

    /// The same subagent, told who on the team it is. Neither provider can do this: the
    /// roster is the project's, and a CLI knows only the label it was spawned under.
    ///
    /// The skill comes back with the name, and replaces whatever the provider called this
    /// thread — Codex nicknames a spawned thread ("Dewey", "Dirac"), and a nickname colours
    /// no tile, groups under nobody, and outlives the run in the ledger.
    func named(in team: [TeamMember]) -> SubagentStatus {
        guard let found = Team.running("\(description) \(agentType)", in: team) else { return self }
        return SubagentStatus(
            id: id, description: description, agentType: found.skill,
            running: running, transcriptURL: transcriptURL, taskID: taskID,
            member: found.member.name)
    }
}

/// The subagents attached to one assigned task, including an empty group while that task
/// waits for a dependency or for the lead to dispatch its first specialist.
struct SubagentTaskGroup: Identifiable {
    let id: String
    let subagents: [SubagentStatus]
}

/// One human-readable line pulled out of a subagent's transcript: the task it was given,
/// each tool it called, that tool's result, and its replies. Everything else in the file —
/// thinking blocks, bookkeeping fields — is left out rather than guessed at.
struct TranscriptLine: Identifiable {
    let id = UUID()
    let label: String
    let text: String
    /// Set on a tool result the provider marked as failed — the one thing a collapsed run
    /// of work still has to be able to say out loud.
    var isError = false
}

/// What both providers share: neither CLI records which notebook task a subagent is for,
/// so the link is the subagent's own label. The engineering-lead skill puts the task id in
/// every name it spawns; Claude keeps that as the Agent call's `description`, Codex slugs
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
