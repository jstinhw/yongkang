import Foundation
import Testing

@testable import YongkangCore

/// Codex 0.154.0, answered yes in a scratch `CODEX_HOME`: a folder outside a repo was filed under
/// its own real path, one inside a repo under the repo's root, and one in a linked worktree
/// under the main repository's root. A trusted parent outside a repo was asked about again.
@Suite struct CodexTrustTests {
    private func config(_ trusted: [String], in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("config.toml")
        let tables = trusted.map { "[projects.\"\($0)\"]\ntrust_level = \"trusted\"\n" }
        try (["model = \"gpt-5\"\n"] + tables).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func aRepoIsTrustedByItsRootAndAPlainFolderByItself() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (plain, repo) = (dir.appendingPathComponent("plain"), dir.appendingPathComponent("repo"))
        let sub = repo.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let roots = try config([physicalPath(plain), physicalPath(repo)], in: dir)
        #expect(CodexProvider.trusts(plain, config: roots) == true)
        #expect(CodexProvider.trusts(sub, config: roots) == true, "the repo's root covers the whole repo")
        let parent = try config([physicalPath(dir)], in: dir)
        #expect(CodexProvider.trusts(plain, config: parent) == false, "a parent outside a repo covers nothing")
        let typed = try config([plain.path], in: dir)
        #expect(CodexProvider.trusts(plain, config: typed) == false, "not under the path as typed")
    }

    @Test func aLinkedWorktreeIsTrustedByItsMainRepository() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (main, worktree) = (dir.appendingPathComponent("main"), dir.appendingPathComponent("wt"))
        try FileManager.default.createDirectory(
            at: main.appendingPathComponent(".git/worktrees/wt"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(physicalPath(main))/.git/worktrees/wt\n"
            .write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        #expect(CodexProvider.trusts(worktree, config: try config([physicalPath(main)], in: dir)) == true)
    }

    @Test func onlyATrustedTableCounts() {
        let toml = """
            [projects."/a"]
            trust_level = "trusted"

            [projects."/b"]
            trust_level = "untrusted"

            [tui]
            trust_level = "trusted"
            """
        #expect(CodexProvider.trustedProjects(in: toml) == ["/a"])
    }

    @Test func noConfigIsNo() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(CodexProvider.trusts(dir, config: dir.appendingPathComponent("config.toml")) == false)
    }
}
