import Foundation

enum AgentCommand {
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Each agent takes an opening prompt, which is how a new
    /// project's notebook conversation starts without anyone typing it.
    ///
    /// Claude Code and Grok accept `--session-id`; Codex gets a marker in its prompt so
    /// its rollout can be found later. Agy has neither and starts prompted sessions with
    /// `--prompt-interactive`.
    static func line(
        directory: String, agent: AgentKind, prompt: String?, sessionID: UUID? = nil,
        brief: Bool = false, noCommit: Bool = false
    ) -> String {
        let briefFlag = agent == .claude && brief ? "--brief " : ""
        let sessionFlag =
            agent == .claude || agent == .grok
            ? sessionID.map { "--session-id \($0.uuidString.lowercased()) " } ?? "" : ""
        let command = "\(agent.command) \(briefFlag)\(noCommit ? denyCommits(agent) : "")\(sessionFlag)"
            .trimmingCharacters(in: .whitespaces)
        let opening =
            agent == .codex
            ? prompt.flatMap { text in sessionID.map { "\(text)\n\n\(marker($0))" } } ?? prompt
            : prompt
        let promptFlag = agent == .agy && opening != nil ? " --prompt-interactive" : ""
        let start = opening.map { "exec \(command)\(promptFlag) \(quoted($0))" } ?? "exec \(command)"
        return "cd \(quoted(directory)) && \(start)"
    }

    /// Commits are the user's, made from the Review screen once they approve the work, so a
    /// lead session and its subagents are refused them outright rather than only asked in
    /// the skill. `=` keeps Claude's variadic flag from swallowing the prompt after it.
    /// ponytail: prefix rules, so `git -C . commit` slips past; the skill text covers that,
    /// and Codex and Agy have no deny flag at all.
    static func denyCommits(_ agent: AgentKind) -> String {
        let rules = ["Bash(git commit:*)", "Bash(git push:*)", "Bash(gh pr create:*)"]
        switch agent {
        case .claude: return "--disallowedTools=\(quoted(rules.joined(separator: ","))) "
        case .grok: return rules.map { "--deny \(quoted($0)) " }.joined()
        default: return ""
        }
    }

    /// Codex picks its own thread id, so `--session-id` has nothing to set on it: the only
    /// join from an app session row back to a rollout on disk is the opening prompt, which
    /// the rollout records verbatim. Every prompted Codex session therefore ends with its
    /// id, and `CodexTranscripts` finds the thread by looking for exactly this line —
    /// without it the app has a live terminal it cannot read a transcript from.
    static func marker(_ sessionID: UUID) -> String {
        "(Yongkang session \(sessionID.uuidString.lowercased()) — bookkeeping, not part of the task.)"
    }

    /// A service is whatever the repo starts with, so no `exec` — the command may be a
    /// pipeline or a shell function, and the login shell has to stay around to run it.
    static func line(directory: String, run command: String) -> String {
        "cd \(quoted(directory)) && \(command)"
    }
}
