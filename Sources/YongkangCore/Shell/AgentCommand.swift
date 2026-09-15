import Foundation

package enum AgentCommand {
    package static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Each agent takes an opening prompt, which is how a new
    /// project's notebook conversation starts without anyone typing it.
    ///
    /// How the CLI is handed the prompt, the session id and the commit rules is its
    /// provider's `launch`.
    package static func line(
        directory: String, agent: AgentKind, prompt: String?, sessionID: UUID? = nil,
        brief: Bool = false, noCommit: Bool = false
    ) -> String {
        let words = agent.provider.launch(prompt: prompt, sessionID: sessionID, brief: brief, noCommit: noCommit)
        return "cd \(quoted(directory)) && exec \(([agent.command] + words).joined(separator: " "))"
    }

    /// Commits are the user's, made from the Review screen once they approve the work, so a
    /// lead session and its subagents are refused them outright rather than only asked in
    /// the skill, by any CLI that has a flag for it.
    /// ponytail: prefix rules, so `git -C . commit` slips past; the skill text covers that,
    /// and Codex and Agy have no deny flag at all.
    static let commitRules = ["Bash(git commit:*)", "Bash(git push:*)", "Bash(gh pr create:*)"]

    /// A service is whatever the repo starts with, so no `exec` — the command may be a
    /// pipeline or a shell function, and the login shell has to stay around to run it.
    package static func line(directory: String, run command: String) -> String {
        "cd \(quoted(directory)) && \(command)"
    }
}
