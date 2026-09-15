import Foundation
import Testing

@testable import YongkangCore

/// The two git calls a refresh makes, read from captured bytes and from real repositories:
/// renames, conflicts, names no line-based parser survives, and the states before the first
/// commit and off any branch.
@Suite struct GitClientTests {
    // MARK: - Captured output

    /// git 2.50.1 mid-merge: `a.txt` and `bin.dat` edited, `conflict.txt` unmerged,
    /// `old name.txt` renamed with `git mv`, and two untracked files, one with a newline in
    /// its name.
    @Test func parsesCapturedPorcelainV2() throws {
        let status = GitClient.parseStatus(Data(try fixture("git/git-2.50.1-status-porcelain-v2.z").utf8))
        #expect(status.oid == "8476a3670cbf5512ad6b8a5096eeea4eb1d95764")
        #expect(status.branch == "main")
        #expect(
            status.untracked == ["has space.txt", "new\nline.txt"],
            "a rename's original path and an unmerged file are not untracked files")
    }

    @Test func parsesTheHeadersOfARepositoryWithNoCommitOrNoBranch() {
        let output = "# branch.oid (initial)\0# branch.head (detached)\0"
        let status = GitClient.parseStatus(Data(output.utf8))
        #expect(status.oid == nil && status.branch == nil)
    }

    @Test func aRenamesOriginalPathIsNeverReadAsARecord() {
        let rename = "2 R. N... 100644 100644 100644 aaaa bbbb R100 new.txt\0? old.txt\0"
        #expect(
            GitClient.parseStatus(Data(rename.utf8)).untracked.isEmpty,
            "the original path that follows a rename is skipped, even when it looks like a record")
    }

    @Test func parsesCapturedNumstat() throws {
        let changes = GitClient.parseNumstat(Data(try fixture("git/git-2.50.1-numstat.z").utf8))
            .sorted { $0.path < $1.path }
        #expect(
            changes
                == [
                    FileChange(path: "a.txt", added: 2, removed: 1, untracked: false),
                    FileChange(path: "bin.dat", added: 0, removed: 0, untracked: false),
                    FileChange(path: "conflict.txt", added: 4, removed: 0, untracked: false),
                    FileChange(path: "new name.txt", added: 0, removed: 0, untracked: false),
                ],
            "a binary file counts nothing, and a rename is listed under its new path")
    }

    // MARK: - Real repositories

    @Test func readsRenamesConflictsAndOddNamesFromARealRepository() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await makeRepository(dir)
        func write(_ name: String, _ text: String) throws {
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try write("a.txt", "one\ntwo\n")
        try write("conflict.txt", "base\n")
        try write("old name.txt", "rename me\nplease\n")
        try Data([0, 1, 2, 3, 0, 255]).write(to: dir.appendingPathComponent("bin.dat"))
        try await git(["add", "--all"], in: dir)
        try await git(["commit", "--quiet", "--message", "Base"], in: dir)
        try await git(["checkout", "--quiet", "-b", "other"], in: dir)
        try write("conflict.txt", "other\n")
        try await git(["commit", "--quiet", "--all", "--message", "Other"], in: dir)
        try await git(["checkout", "--quiet", "main"], in: dir)
        try write("conflict.txt", "main\n")
        try await git(["commit", "--quiet", "--all", "--message", "Main"], in: dir)
        let merge = try await AsyncProcess.run(
            URL(fileURLWithPath: "/usr/bin/env"), ["git", "merge", "other"], in: dir,
            environment: GitClient.environment)
        try #require(merge.status != 0, "the merge stops on the conflict")
        try await git(["mv", "old name.txt", "new name.txt"], in: dir)
        try write("a.txt", "one\n2\nthree\n")
        try Data([9, 0, 9, 0, 255, 254]).write(to: dir.appendingPathComponent("bin.dat"))
        try write("has space.txt", "x\n")
        try write("new\nline.txt", "y\n")

        let status = try #require(await RepoStatus.read(in: dir))
        #expect(
            status.changes.map(\.path)
                == ["a.txt", "bin.dat", "conflict.txt", "has space.txt", "new\nline.txt", "new name.txt"])
        #expect(status.changes.filter(\.untracked).map(\.path) == ["has space.txt", "new\nline.txt"])
        #expect(status.branch == "main")
        #expect(status.head?.hasSuffix(" Main") == true)
    }

    @Test func aRepositoryWithNoCommitListsItsFilesAndNamesItsBranch() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await makeRepository(dir)
        try "x\n".write(to: dir.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        let status = try #require(await RepoStatus.read(in: dir))
        #expect(status.changes.map(\.path) == ["first.txt"])
        #expect(status.head == nil && status.oid == nil)
        #expect(status.branch == "main")
    }

    @Test func aDetachedHeadHasACommitAndNoBranch() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await makeRepository(dir)
        try "x\n".write(to: dir.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "--all"], in: dir)
        try await git(["commit", "--quiet", "--message", "First"], in: dir)
        try await git(["checkout", "--quiet", "--detach"], in: dir)
        let status = try #require(await RepoStatus.read(in: dir))
        #expect(status.branch == nil)
        #expect(status.head?.hasSuffix(" First") == true)
    }

    @Test func theSubjectIsOnlyAskedForWhenTheCommitMoves() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await makeRepository(dir)
        try "x\n".write(to: dir.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "--all"], in: dir)
        try await git(["commit", "--quiet", "--message", "First"], in: dir)
        let first = try #require(await RepoStatus.read(in: dir))

        // A head no `git log` would print: if it survives the read, log was not run.
        let remembered = RepoStatus(head: "remembered", oid: first.oid)
        #expect(await RepoStatus.read(in: dir, after: remembered)?.head == "remembered")

        try await git(["commit", "--quiet", "--allow-empty", "--message", "Second"], in: dir)
        #expect(
            await RepoStatus.read(in: dir, after: remembered)?.head?.hasSuffix(" Second") == true,
            "a new commit is a new id, and its subject is read again")
    }
}
