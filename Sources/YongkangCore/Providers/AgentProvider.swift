import Foundation

/// Everything Yongkang knows about one agent CLI: how to start it, where it keeps a session's
/// transcript, subagents and token usage, and what its screen looks like when it needs the
/// user. One per `AgentKind`, in `Providers/<CLI>/`, so supporting another CLI, or following a
/// format change in one, is that folder and its fixtures (docs/providers.md).
///
/// None of what a provider reads is a published API. A format change upstream makes a reader
/// find nothing, rather than break anything the app depends on.
package protocol AgentProvider: Sendable {
    var kind: AgentKind { get }
    /// What the agent switch and a session's inspector call it.
    var displayName: String { get }
    /// The SF Symbol on the session's row.
    var systemImage: String { get }
    /// What starts a skill in a prompt: `/` for most CLIs, `$` for Codex.
    var skillPrefix: String { get }

    /// What follows the executable on the command line, already shell-quoted and joined with
    /// spaces by `AgentCommand.line`, ending with the opening prompt when there is one.
    /// `sessionID` is the app's id for the row, for a CLI that can be handed it or made to
    /// record it. `noCommit` denies `AgentCommand.commitRules`,
    /// where the CLI has a flag for it.
    func launch(prompt: String?, sessionID: UUID?, noCommit: Bool, reading: [String]) -> [String]
    /// What follows the executable to reopen a session an earlier run of the app started, with
    /// its conversation, after the app was quit or crashed. Nil when the CLI kept nothing to
    /// reopen it from, which is a session that never got going: it is started over instead.
    func resume(sessionID: UUID, project: URL, noCommit: Bool, reading: [String]) async -> [String]?
    /// Whether the CLI can be handed folders beyond the one it starts in, which is what
    /// `reading` in `launch` becomes. A CLI that cannot is never offered any.
    var readsOtherFolders: Bool { get }
    /// The words that make the CLI answer one prompt on stdout and exit, with no session, for
    /// what has to be asked before a session exists. Already shell-quoted, like `launch`.
    func ask(prompt: String) -> [String]

    // The reads a provider may answer from state it keeps between calls are `async`, because
    // it keeps that state in an actor: its usage cursors, or Codex's index of rollouts.

    /// The session's own transcript. Nil when the CLI keeps none, or it can't be found yet.
    func transcriptURL(session: UUID, project: URL) async -> URL?
    /// Where the session's token usage is written: its transcript, unless the CLI keeps it apart.
    func usageURL(session: UUID, project: URL) async -> URL?
    /// The agents the session has spawned, each with the task out of `taskIDs` its label names.
    func subagents(session: UUID, project: URL, taskIDs: [String]) async -> [SubagentStatus]
    /// A transcript's lines as the viewer shows them.
    func transcript(at url: URL) -> [TranscriptLine]
    /// Every turn's spend in a usage file so far. Only what was written since the last call
    /// is parsed.
    func usage(at url: URL) async -> [UsageSample]

    /// Why the CLI's rendered screen is waiting on the user, such as a trust question, or nil.
    /// Match the question and its controls, never a mention of it in ordinary output.
    /// Only a question about the folder: the keys that answer it in one session are typed into
    /// every other session of the CLI in that folder that is asking it (`TerminalRegistry`).
    func attentionReason(screen: String) -> String?
    /// Whether the CLI's own record says it may work in `folder`: false while a session of it
    /// there would ask first. Nil when the record can't be read right now. True, by default,
    /// for a CLI that never asks.
    func trusts(_ folder: URL) async -> Bool?
    /// How to show one of its subagents live in the session's terminal. Nil when the CLI can't.
    var childView: ChildView? { get }
}

extension AgentProvider {
    package func usageURL(session: UUID, project: URL) async -> URL? {
        await transcriptURL(session: session, project: project)
    }

    package func trusts(_ folder: URL) async -> Bool? { true }
}

/// A CLI's own picker of child agents. `TerminalRegistry` types `command`, then walks the
/// picker's rows until the selected one names the child.
package struct ChildView: Sendable {
    /// Typed to open the picker.
    package let command: String
    /// The row for the session's own conversation, for a CLI whose child view takes the
    /// conversation over (Codex), so going back is another pick. Nil for a view drawn over the
    /// conversation (Claude Code): Esc closes it, and with only one child the CLI opens that
    /// child without showing the picker.
    package let parentRow: String?
    /// Whether the lowercased screen shows the picker. Selection keys go only to a picker the
    /// registry recognises, never into a chat prompt.
    package let isPicker: @Sendable (_ screen: String) -> Bool

    package init(command: String, parentRow: String?, isPicker: @escaping @Sendable (_ screen: String) -> Bool) {
        self.command = command
        self.parentRow = parentRow
        self.isPicker = isPicker
    }
}

/// Where the CLIs file a folder's answer to their trust question.
enum TrustedFolder {
    /// The folder as `getcwd` gives it from inside, which is what Claude Code, Codex and Agy
    /// file an answer under: symlinks resolved, `/private` kept. `realpath`, not
    /// `resolvingSymlinksInPath`, which drops a leading `/private`.
    static func path(of folder: URL) -> String {
        guard let resolved = realpath(folder.path, nil) else { return folder.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// A CLI's JSON settings. Empty when there is no file yet, which is a CLI that has never
    /// been allowed anywhere; nil when there is one it can't read, such as one caught mid-write.
    static func json(at url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func home(_ path: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
    }
}

/// The question a terminal is asking the user, read off what it has rendered. SwiftTerm has
/// already applied the escape sequences and joined split PTY writes by then.
package enum AgentPrompt {
    /// Every provider is asked, not only the session's own: the terminal doesn't know which CLI
    /// drew it, and no two CLIs draw the same question with the same answers.
    package static func reason(in screen: String) -> String? {
        AgentKind.allCases.lazy.compactMap { $0.provider.attentionReason(screen: screen) }.first
    }

    /// The screen as a person reads it: lowercased, with every run of blanks as one space.
    /// Cursor-addressed TUIs leave blank cells as NUL, even though they display as spaces.
    static func visibleText(_ screen: String) -> String {
        screen.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "\0" }).joined(separator: " ")
    }
}
