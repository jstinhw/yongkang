import Foundation

/// Agy (`agy`). It runs in its live terminal only: nothing it writes to disk is read.
package struct AgyProvider: AgentProvider {
    package init() {}

    package var kind: AgentKind { .agy }
    package var displayName: String { "Agy" }
    package var systemImage: String { "a.circle" }
    package var skillPrefix: String { "/" }
    /// The paths its own skill-migration notes give.
    package var skillFolders: SkillFolders {
        SkillFolders(project: [".agents/skills", "_agents/skills"], home: [".gemini/config/skills"])
    }

    /// No session id and no deny flag. A prompted session starts with `--prompt-interactive`.
    package var readsOtherFolders: Bool { true }

    package func launch(prompt: String?, sessionID: UUID?, noCommit: Bool, reading: [String]) -> [String] {
        reading.map { "--add-dir \(AgentCommand.quoted($0))" }
            + (prompt.map { ["--prompt-interactive", AgentCommand.quoted($0)] } ?? [])
    }

    /// ponytail: Agy's conversation id is never read, so `--continue` reopens the folder's newest
    /// one — the wrong one for all but the last of several Agy sessions in a folder. Read its
    /// id off disk for `--conversation` if that turns out to matter.
    package func resume(sessionID: UUID, project: URL, noCommit: Bool, reading: [String]) async -> [String]? {
        launch(prompt: nil, sessionID: nil, noCommit: noCommit, reading: reading) + ["--continue"]
    }

    package func ask(prompt: String) -> [String] {
        ["-p", AgentCommand.quoted(prompt)]
    }

    package func transcriptURL(session: UUID, project: URL) async -> URL? {
        nil
    }

    package func subagents(session: UUID, project: URL, taskIDs: [String]) async -> [SubagentStatus] {
        []
    }

    package func transcript(at url: URL) -> [TranscriptLine] {
        []
    }

    package func usage(at url: URL) async -> [UsageSample] {
        []
    }

    package func trusts(_ folder: URL) async -> Bool? {
        Self.trusts(folder, settings: TrustedFolder.home(".gemini/antigravity-cli/settings.json"))
    }

    /// 1.2.4 asks in every folder it has no answer for, and files a yes as the folder's own
    /// path (`TrustedFolder.path`) in `trustedWorkspaces`: not its repo's root, and a trusted
    /// parent covers nothing.
    static func trusts(_ folder: URL, settings: URL) -> Bool? {
        guard let object = TrustedFolder.json(at: settings) else { return nil }
        return (object["trustedWorkspaces"] as? [String])?.contains(TrustedFolder.path(of: folder)) == true
    }

    /// Captured in `Fixtures/agy/agy-1.2.4-trust-screen.ansi`.
    package func attentionReason(screen: String) -> String? {
        let text = AgentPrompt.visibleText(screen)
        guard text.contains("do you trust the contents of this project?"), text.contains("yes, i trust this folder"),
            text.contains("no, exit")
        else { return nil }
        return "Agy needs you to decide whether to trust this folder."
    }

    package var childView: ChildView? { nil }
}
