import Foundation
import Testing

@testable import YongkangCore

@Suite struct NotebookSnapshotTests {
    // The poll's guard: a notebook nobody wrote to reads back equal, so the project keeps
    // the snapshot it has.
    @Test func rereadingAnUnchangedNotebookIsEqual() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = try NotebookLoaderTests.makeSample(in: tmp).root

        let first = NotebookSnapshot().reread(root: root, frontmatter: true, records: true)
        #expect(first.cards.contains { $0.id == "launch-beta" }, "the sample was read")
        #expect(first.reread(root: root, frontmatter: true, records: true) == first)
    }

    // Outside the entered project only the file list is read; the board it last showed
    // stays rather than blanking.
    @Test func aCheapReadKeepsWhatItSkips() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = try NotebookLoaderTests.makeSample(in: tmp).root
        let first = NotebookSnapshot().reread(root: root, frontmatter: true, records: true)

        _ = try NotebookFormat.create(.task, title: "Ship it", in: root, project: "launch-beta")
        let cheap = first.reread(root: root, frontmatter: false, records: false)
        #expect(cheap.entries != first.entries, "the file list is always read")
        #expect(cheap.cards == first.cards && cheap.team == first.team && cheap.records == first.records)

        let full = cheap.reread(root: root, frontmatter: true, records: false)
        #expect(full.cards.contains { $0.id == "ship-it" })
    }
}
