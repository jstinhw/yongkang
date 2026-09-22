import Foundation
import Testing

@testable import YongkangCore

/// Claude Code 2.1.278, opened through a symlink and answered yes, filed the answer under the
/// folder's real path, `/private` and all. The temporary directory is under `/var`, itself a
/// symlink to `/private/var`, so every folder here has both spellings.
@Suite struct ClaudeTrustTests {
    private func config(_ projects: [String: Bool], in dir: URL) throws -> URL {
        let entries = projects.mapValues { ["hasTrustDialogAccepted": $0] }
        let url = dir.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: ["projects": entries]).write(to: url)
        return url
    }

    /// What `getcwd` says inside `url`, spelled out rather than resolved, so the test and the
    /// code under it can't agree by sharing a mistake.
    private func physical(_ url: URL) -> String {
        url.path.hasPrefix("/var/") ? "/private" + url.path : url.path
    }

    @Test func readsTheAnswerFiledUnderTheFoldersRealPath() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real")
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let yes = try config([physical(real): true], in: dir)
        #expect(ClaudeCodeProvider.trusts(real, config: yes) == true)
        #expect(ClaudeCodeProvider.trusts(link, config: yes) == true, "a symlink is the folder it points at")

        let typed = try config([real.path: true], in: dir)
        #expect(ClaudeCodeProvider.trusts(real, config: typed) == false, "not under the path as typed")
        let parent = try config([physical(dir): true], in: dir)
        #expect(ClaudeCodeProvider.trusts(real, config: parent) == false, "nor under a parent's")
        #expect(ClaudeCodeProvider.trusts(real, config: try config([physical(real): false], in: dir)) == false)
    }

    @Test func noRecordIsNoButAnUnreadableOneSaysNothing() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(".claude.json")
        #expect(ClaudeCodeProvider.trusts(dir, config: url) == false, "Claude Code has never been allowed anywhere")

        try "{\"projects\": {".write(to: url, atomically: true, encoding: .utf8)
        #expect(ClaudeCodeProvider.trusts(dir, config: url) == nil, "one caught mid-write")
    }
}
