import Foundation
import Testing

@testable import YongkangCore

/// Agy 1.2.4, answered yes: every folder, in a repo or not, was filed as its own real path in
/// `trustedWorkspaces`, and a folder under a trusted one was asked about again.
@Suite struct AgyTrustTests {
    private func settings(_ trusted: [String], in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: ["model": "flash", "trustedWorkspaces": trusted]).write(to: url)
        return url
    }

    @Test func readsTheFoldersOwnRealPath() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        #expect(AgyProvider.trusts(folder, settings: try settings([physicalPath(folder)], in: dir)) == true)
        #expect(AgyProvider.trusts(folder, settings: try settings([physicalPath(dir)], in: dir)) == false)
        #expect(AgyProvider.trusts(folder, settings: try settings([folder.path], in: dir)) == false)
        #expect(AgyProvider.trusts(folder, settings: dir.appendingPathComponent("none.json")) == false)
    }
}
