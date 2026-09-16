import Foundation

/// A described project's folder name, chosen by the agent the user picked rather than cut out of
/// the words they typed.
///
/// It is asked before the folder exists, in a one-shot run of the CLI, because the session that
/// writes the notebook runs inside that folder: renaming it under a live CLI would strand the
/// CLI's own record of where it is, and the transcript the app finds by that path.
package enum ProjectNaming {
    /// The CLI ran but left nothing to name the folder with. `detail` is the last thing it said
    /// on stderr, which is usually the reason: not signed in, no network, a flag it rejected.
    package struct Failure: LocalizedError {
        package let agent: AgentKind
        package let detail: String

        package var errorDescription: String? {
            let said = detail.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            let reason = said.isEmpty ? "it gave no name" : said
            return "\(agent.displayName) could not name the project: \(reason)"
        }
    }

    static func prompt(_ description: String) -> String {
        """
        Choose the folder name for the new software project described below. Reply with the \
        name and nothing else: one to three lowercase words joined by hyphens, such as \
        weather-cli. Do not run any tools or create anything.

        \(description)
        """
    }

    /// The name out of whatever the CLI printed. The last line, because a CLI or the login
    /// shell around it can print something first.
    ///
    /// ponytail: a reply that ignores the format still becomes a name, cut to its first five
    /// words. Reject it and ask again if agents start answering in sentences.
    package static func name(from answer: String) -> String? {
        let line = answer.split(whereSeparator: \.isNewline)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let words = line.map { NotebookFormat.slug(String($0)).split(separator: "-") } ?? []
        return words.isEmpty ? nil : words.prefix(5).joined(separator: "-")
    }

    /// Runs the way a session does, through the login shell, so the CLI is on PATH. It runs in
    /// the temporary folder: nothing of the user's is where it starts, and nothing is written.
    /// Cancelling the calling task terminates the CLI.
    package static func ask(
        _ agent: AgentKind, description: String, shell: [String] = ["/bin/zsh", "-ilc"]
    ) async throws -> String {
        let words = [agent.command] + agent.provider.ask(prompt: prompt(description))
        let line = AgentCommand.line(directory: NSTemporaryDirectory(), run: "exec " + words.joined(separator: " "))
        let output = try await AsyncProcess.run(
            URL(fileURLWithPath: shell[0]), Array(shell.dropFirst()) + [line], stderr: .capture)
        if output.status == 0, let name = name(from: output.text) { return name }
        let said = String(decoding: output.stderr, as: UTF8.self).split(whereSeparator: \.isNewline)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        throw Failure(agent: agent, detail: said.map { String($0.prefix(200)) } ?? "")
    }
}
