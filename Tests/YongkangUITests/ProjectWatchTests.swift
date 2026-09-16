import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The console used to re-list every open project every two seconds whether or not anything had
/// moved. It now reads when the disk says something did, with a slow beat behind it for the
/// events FSEvents drops. Both halves have to work, and the second one is the half nobody would
/// notice was broken.
@Suite @MainActor struct ProjectWatchTests {
    /// A folder named `name` under `tmp` with a notebook holding one task.
    private func notebook(_ name: String, in tmp: URL) throws -> URL {
        let directory = tmp.appendingPathComponent(name)
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: NotebookFormat.root(in: directory), project: nil)
        return directory
    }

    @Test func aPageWrittenIntoTheNotebookReachesTheBoardWithoutBeingAskedFor() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = AppModel()
        let project = app.open(try notebook("app", in: tmp))
        // An hour, so the watcher is the only thing in this test that could reload anything.
        app.start(polling: .seconds(3600))
        defer { app.stop() }
        await app.reloadNow()
        try #require(!project.snapshot.cards.contains { $0.id == "ship-it" })

        _ = try NotebookFormat.create(.task, title: "Ship it", in: project.notebookRoot, project: nil)
        #expect(
            try await eventually { project.snapshot.cards.contains { $0.id == "ship-it" } },
            "the page an agent just wrote is on the board, with nothing on a clock to put it there")
    }

    /// FSEvents drops events on network volumes and across sleep, and a board that had quietly
    /// stopped updating would be a miserable bug to reproduce. The watch is taken away here so
    /// that only the beat behind it can be what notices.
    @Test func theSafetyPollStillReadsWhenNoEventArrives() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = AppModel()
        let project = app.open(try notebook("app", in: tmp))
        app.start(polling: .milliseconds(200))
        defer { app.stop() }
        await app.reloadNow()
        project.stopWatching()

        _ = try NotebookFormat.create(.task, title: "Ship it", in: project.notebookRoot, project: nil)
        #expect(
            try await eventually { project.snapshot.cards.contains { $0.id == "ship-it" } },
            "the beat caught what the watcher would have missed")
    }

    /// Closing a project ends its watch, so a folder nobody has open costs nothing at all.
    @Test func closingAProjectEndsItsWatch() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = AppModel()
        let project = app.open(try notebook("app", in: tmp))
        app.start(polling: .seconds(3600))
        defer { app.stop() }
        await app.reloadNow()

        app.close(project)
        _ = try NotebookFormat.create(.task, title: "Ship it", in: project.notebookRoot, project: nil)
        try await Task.sleep(for: .milliseconds(500))
        #expect(
            !project.snapshot.cards.contains { $0.id == "ship-it" },
            "nothing read it, because nothing is watching it and it is no longer in the reload")
    }
}
