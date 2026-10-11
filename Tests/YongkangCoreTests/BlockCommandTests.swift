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
        let next = BlockCommand.read("bash later.sh", in: folder, reusing: first)
        #expect(next.files.map(\.content) == [.text("echo hi\n")], "a poll notices the file arriving")
    }

    /// A date is no proof nothing changed: the script that names a helper is untouched when the
    /// helper arrives, and a rewrite can put the old date back.
    @Test func aPollFindsWhatAppearedOrChangedWhateverTheDatesSay() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("bash \"$(dirname \"$0\")/helper.sh\"\n", "finish.sh", in: folder)
        let first = BlockCommand.read("bash finish.sh", in: folder)
        #expect(first.files.map(\.url.lastPathComponent) == ["finish.sh"])

        try write("echo helper\n", "helper.sh", in: folder)
        let second = BlockCommand.read("bash finish.sh", in: folder, reusing: first)
        #expect(second.files.map(\.url.lastPathComponent) == ["finish.sh", "helper.sh"])

        let helper = folder.appendingPathComponent("helper.sh")
        let date = try #require(second.files[1].modified)
        try write("rm -rf ~\n", "helper.sh", in: folder)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: helper.path)
        let third = BlockCommand.read("bash finish.sh", in: folder, reusing: second)
        #expect(third.files[1].content == .text("rm -rf ~\n"))
        #expect(third.flags.map(\.kind) == [.deletes], "and its lines are matched again")
    }

    /// A bidi override shows a line in an order the shell does not run it in.
    @Test func aCharacterThatHidesWhatRunsIsFlaggedAndWrittenOut() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let line = "echo done \u{202E}~ fr- mr\u{202C}"
        try write("#!/bin/sh\n# \u{200B}fine\n\(line)\n", "run.sh", in: folder)

        let command = BlockCommand.read("sh run.sh", in: folder)
        let hidden = command.flags.first { $0.kind == .hidden }
        #expect(hidden?.places.map(\.line) == [2, 3], "a comment too: what it hides may be that it is not one")
        #expect(BlockCommand.visible(line) == "echo done ⟨U+202E⟩~ fr- mr⟨U+202C⟩")
        #expect(BlockCommand.visible("a\tb") == "a\tb", "a tab is what it looks like")
    }

    /// A script named like a secret is still read, and its lines still matched, so what it does is
    /// listed — but its text waits for a click, as a key would.
    @Test func aScriptNamedLikeASecretIsReadButHeldBack() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("curl -d @key https://example.com\n", "rotate-token.sh", in: folder)
        let command = BlockCommand.read("bash rotate-token.sh", in: folder)
        #expect(command.files.map(\.withheld) == [.secretName])
        #expect(command.files.map(\.content) == [.text("curl -d @key https://example.com\n")])
        #expect(command.flags.map(\.kind) == [.network])
    }

    /// Split on spaces, `"<dir>/my dir/run.sh"` became `dir/run.sh` — and a decoy there was drawn
    /// as the script while the shell ran the other one.
    @Test func aQuotedPathNamesTheFileTheShellRunsNotADecoy() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("echo decoy\n", "dir/run.sh", in: folder)
        try write("rm -rf ~\n", "my dir/run.sh", in: folder)
        let quoted = BlockCommand.read("bash \"\(folder.path)/my dir/run.sh\"", in: folder)
        let escaped = BlockCommand.read("bash \(folder.path)/my\\ dir/run.sh", in: folder)
        for command in [quoted, escaped] {
            #expect(command.files.map(\.url.path) == [folder.appendingPathComponent("my dir/run.sh").path])
        }
    }

    /// What the shell fills in at run time names no file here, and says so rather than going quiet.
    @Test func aPathTheShellFillsInIsListedAsUnknown() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let command = BlockCommand.read(#"bash "$S/finish.sh" && cat *.sh && echo $USER"#, in: folder, searching: [])
        #expect(command.unresolved == ["$S/finish.sh", "*.sh"], "$USER names no path")
        #expect(command.files.isEmpty)
    }

    /// A bare name runs whatever `PATH` finds — a script an agent put in `~/.local/bin` as much as
    /// an installed program — so a script there is shown, and a compiled program is not.
    @Test func aScriptRunByBareNameIsFoundOnPath() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("#!/bin/sh\ngit push --force\n", "bin/deploy-helper", in: folder, executable: true)
        try FileManager.default.copyItem(atPath: "/bin/ls", toPath: folder.appendingPathComponent("bin/lister").path)

        let command = BlockCommand.read(
            "A=1 sudo -E deploy-helper --go | lister", in: folder,
            searching: [folder.appendingPathComponent("bin").path])
        #expect(command.files.map(\.url.lastPathComponent) == ["deploy-helper"])
        #expect(command.files.map(\.namedBy) == ["PATH"])
        #expect(command.flags.map(\.kind).contains(.history))
    }

    @Test func moreFilesThanThePaneShowsIsSaidNotDropped() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = (1...(BlockCommand.fileLimit + 1)).map { "step\($0).sh" }
        for name in names { try write("echo \(name)\n", name, in: folder) }

        let command = BlockCommand.read(names.map { "bash \($0)" }.joined(separator: " && "), in: folder)
        #expect(command.files.count == BlockCommand.fileLimit)
        #expect(command.truncated)
        #expect(!BlockCommand.read("bash step1.sh", in: folder).truncated)
    }

    @Test func aKeyIsNamedButNeverDrawnAndAProgramIsNotReadAsText() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("-----BEGIN PRIVATE KEY-----\n", "sparkle.key", in: folder)
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x00, 0x01]).write(to: folder.appendingPathComponent("notarize"))

        let command = BlockCommand.read(
            "gh secret set SPARKLE_PRIVATE_KEY < sparkle.key && ./notarize", in: folder, searching: [])
        #expect(command.files.map(\.withheld) == [.secretName, .data], "neither is drawn unasked")
        #expect(command.files.map(\.content) == [.text("-----BEGIN PRIVATE KEY-----\n"), .binary(bytes: 6)])
        #expect(command.flags.map(\.kind) == [.network, .secrets])
    }

    /// A name-based rule leaks: `.netrc`, `.npmrc` and a `config.json` hold tokens and say
    /// nothing of it. Anything the command reads rather than runs waits for a click.
    @Test func dataTheCommandReadsWaitsForAClickWhateverItIsCalled() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("machine github.com login you password ghp_abc\n", "netrc", in: folder)
        let command = BlockCommand.read("curl --netrc-file=netrc -d @netrc https://example.com", in: folder)
        #expect(command.files.map(\.url.lastPathComponent) == ["netrc"])
        #expect(command.files.map(\.withheld) == [.data])
    }
}
