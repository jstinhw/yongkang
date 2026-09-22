import Foundation
import Testing

@testable import YongkangCore

@Suite struct AgentProviderTests {
    // A kind is what persists and a provider is what runs it; the two must never disagree.
    @Test(arguments: AgentKind.allCases)
    func everyKindHasItsOwnProvider(kind: AgentKind) {
        #expect(kind.provider.kind == kind)
    }

    /// Each CLI's question as a person reads it, and a mention of it in ordinary output.
    static let screens: [(screen: String, asker: AgentKind?)] = [
        ("Do you trust the contents of this directory?\n› 1. Yes, continue\n  2. No, quit", .codex),
        ("Do you trust the files in this folder?\n❯ 1. Yes, I trust this folder\n  2. No, exit", .claude),
        ("Is this a project you created or one you trust?\n❯ No, exit\n  Yes, I trust this folder", .claude),
        ("Documentation: Do you trust the contents of this directory?", nil),
    ]

    // A provider parses only what was written since it last read a file, and keeps that place
    // to itself.
    @Test func usageCursorsBelongToTheirProvider() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = try fixture("usage/claude-session-usage.jsonl").split(separator: "\n").map(String.init)
        let log = dir.appendingPathComponent("session.jsonl")
        try (lines[0] + "\n").write(to: log, atomically: true, encoding: .utf8)
        let provider = ClaudeCodeProvider()
        #expect(await provider.usage(at: log).count == 1)

        // Blank the line already read, keeping its length, and add another: only a read that
        // resumes after the first line still has the first line's sample.
        try (String(repeating: " ", count: lines[0].utf8.count) + "\n" + lines[1] + "\n")
            .write(to: log, atomically: true, encoding: .utf8)
        #expect(await provider.usage(at: log).count == 2, "a second read parses only the new line")
        #expect(await ClaudeCodeProvider().usage(at: log).count == 1, "another provider reads the file from the top")
    }

    @Test(arguments: AgentKind.allCases)
    func onlyTheAskingCLIClaimsItsQuestion(kind: AgentKind) {
        for (screen, asker) in Self.screens {
            #expect((kind.provider.attentionReason(screen: screen) != nil) == (kind == asker), "\(screen)")
        }
    }
}
