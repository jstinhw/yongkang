import Foundation
import Testing

@testable import YongkangCore

/// What the pane beside a session shows before the user runs a command an agent handed them.
/// Shaped on the one that started it: a script in the agent's scratch folder, calling a second
/// script beside it, which put a downloaded program first on `PATH`.
@Suite struct BlockCommandTests {
    private func write(_ text: String, _ name: String, in folder: URL, executable: Bool = false) throws {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    /// The scratch folder as the agent left it: two scripts, the program, and output nobody runs.
    private func scratch() throws -> URL {
        let folder = try makeTemporaryDirectory()
        try write(
            """
            #!/bin/bash
            S=$(cd "$(dirname "$0")" && pwd)
            bash "$S/rewrite.sh" --apply
            # then git push the result
            git remote remove origin
            git push -u origin main
            """, "finish.sh", in: folder)
        try write(
            """
            #!/bin/bash
            rm -rf "$S/w"
            PATH=$S/tool:$PATH git filter-repo --force
            """, "rewrite.sh", in: folder)
        try write("#!/usr/bin/env python3\nprint('filter')\n", "tool/git-filter-repo", in: folder, executable: true)
        try write("60 MB of log nobody runs\n", "old-log.txt", in: folder)
        return folder
    }

    @Test func everyScriptBehindTheCommandIsShownWhole() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let command = BlockCommand.read("bash \(folder.path)/finish.sh", in: folder)

        #expect(
            command.files.map(\.url.lastPathComponent) == ["finish.sh", "rewrite.sh", "git-filter-repo"],
            "the script, the one it calls, and the program the second puts on PATH — and not the log")
        #expect(command.files.map(\.namedBy) == [nil, "finish.sh", "rewrite.sh"])
        guard case .text(let text) = command.files[0].content else {
            Issue.record("the command's own script is drawn in full")
            return
        }
        #expect(text.contains("git remote remove origin"))
    }

    @Test func linesThatReachOutsideAreFlaggedButCommentsAreNot() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let command = BlockCommand.read("bash \(folder.path)/finish.sh", in: folder)
        let finish = command.files[0].url

        func lines(_ kind: BlockCommand.Kind) -> [Int] {
            command.flags.first { $0.kind == kind }?.places.filter { $0.file == finish }.map(\.line) ?? []
        }
        #expect(lines(.network) == [6], "the push, not the comment above the remote change that mentions one")
        #expect(lines(.remote) == [5])
        #expect(command.flags.contains { $0.kind == .deletes }, "rewrite.sh's rm -rf")
        #expect(command.flags.contains { $0.kind == .path }, "rewrite.sh putting its own folder first on PATH")
        #expect(command.flagged(finish) == [5, 6])
    }

    @Test func wordsThatAreNotFilesStayWordsAndTheCommandIsStillRead() {
        let command = BlockCommand.read("git push -u origin main", in: URL(fileURLWithPath: "/nonexistent"))
        #expect(command.files.isEmpty)
        #expect(command.flags.map(\.kind) == [.network])
        #expect(command.flags[0].places == [BlockCommand.Place(file: nil, line: 1)], "the command line itself")
    }

    /// The agent may name the script before it has finished writing it.
    @Test func aScriptNotWrittenYetShowsAsMissingThenAppears() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = BlockCommand.read("bash later.sh", in: folder)
        #expect(first.files.map(\.content) == [.missing])

        try write("echo hi\n", "later.sh", in: folder)
        #expect(!first.isCurrent, "a poll notices the file arriving")
        #expect(BlockCommand.read("bash later.sh", in: folder).files.map(\.content) == [.text("echo hi\n")])
    }

    @Test func aKeyIsNamedButNeverDrawnAndAProgramIsNotReadAsText() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("-----BEGIN PRIVATE KEY-----\n", "sparkle.key", in: folder)
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x00, 0x01]).write(to: folder.appendingPathComponent("notarize"))

        let command = BlockCommand.read(
            "gh secret set SPARKLE_PRIVATE_KEY < sparkle.key && ./notarize", in: folder)
        #expect(command.files.map(\.content) == [.secret, .binary(bytes: 6)])
        #expect(command.flags.map(\.kind) == [.network, .secrets])
    }
}
