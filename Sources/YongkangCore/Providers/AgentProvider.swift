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
    /// record it. `brief` is asked for a lead. `noCommit` denies `AgentCommand.commitRules`,
    /// where the CLI has a flag for it.
    func launch(prompt: String?, sessionID: UUID?, brief: Bool, noCommit: Bool) -> [String]

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
    func attentionReason(screen: String) -> String?
    /// How to show one of its subagents live in the session's terminal. Nil when the CLI can't.
    var childView: ChildView? { get }
}

extension AgentProvider {
    package func usageURL(session: UUID, project: URL) async -> URL? {
        await transcriptURL(session: session, project: project)
    }
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

/// The question a terminal is asking the user, read off what it has rendered. SwiftTerm has
/// already applied the escape sequences and joined split PTY writes by then.
package enum AgentPrompt {
    /// Every provider is asked, not only the session's own: the terminal doesn't know which CLI
    /// drew it, and no two CLIs ask the same question.
    package static func reason(in screen: String) -> String? {
        AgentKind.allCases.lazy.compactMap { $0.provider.attentionReason(screen: screen) }.first
    }

    /// The screen as a person reads it: lowercased, with every run of blanks as one space.
    /// Cursor-addressed TUIs leave blank cells as NUL, even though they display as spaces.
    static func visibleText(_ screen: String) -> String {
        screen.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "\0" }).joined(separator: " ")
    }
}
