import os

/// Where the app says what went wrong when a read or a parser found nothing. The CLIs this
/// console reads change their formats often, and a silent `try?` turns that into an empty
/// pane with no way to tell an upstream change from a bug of ours. `log show --predicate
/// 'subsystem == "ai.yongkang.Yongkang"'` answers it instead (D14 in `docs/refactor-plan.md`).
///
/// **Nothing leaves the Mac, and nothing a person or an agent wrote is ever logged.** Paths,
/// counts, exit statuses and error descriptions only — never file contents, prompt bodies,
/// transcript lines, notebook text or anything typed into a terminal. Everything logged here
/// is marked `.public` on purpose, because a redacted path says nothing; that is exactly why
/// what goes in has to stay to the list above.
///
/// Log the unexpected. A poll that found nothing new is the normal case and says nothing.
package enum Log {
    /// The app's bundle ID, spelt out rather than read from `Bundle.main`: under `swift test`
    /// and in `shots` the main bundle is the runner's, and the predicate above has to match
    /// whichever of them wrote the line.
    private static let subsystem = "ai.yongkang.Yongkang"

    /// Reading and writing `.notebook/` — pages, the team roster, blocks, the usage ledger —
    /// and the FSEvents watch that says when to read them again.
    package static let notebook = Logger(subsystem: subsystem, category: "notebook")
    /// Running git and reading what it said.
    package static let git = Logger(subsystem: subsystem, category: "git")
    /// The PTYs the agents run in.
    package static let terminal = Logger(subsystem: subsystem, category: "terminal")
    /// The agent CLIs' own files: transcripts, rollouts, usage.
    package static let providers = Logger(subsystem: subsystem, category: "providers")
}
