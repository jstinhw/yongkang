import Foundation
import Observation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The models are the window's one mutation boundary. What these lock in is what a screen
/// sees of it: a poll that finds nothing new, or news in another project, invalidates nothing.
@Suite @MainActor struct ProjectModelTests {
    /// A folder named `name` under `tmp` with a notebook holding one task.
    private func notebook(_ name: String, in tmp: URL) throws -> URL {
        let directory = tmp.appendingPathComponent(name)
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: NotebookFormat.root(in: directory), project: nil)
        return directory
    }

    /// Whether `change` writes anything `read` reads. Observation calls back synchronously on
    /// the first such write, so there is nothing to wait for.
    private func invalidates(_ read: @autoclosure () -> Any, by change: () throws -> Void) rethrows -> Bool {
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        _ = withObservationTracking(read) { flag.fired = true }
        try change()
        return flag.fired
    }

    @Test func reloadingAnUnchangedNotebookKeepsItsSnapshot() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = ProjectModel(directory: try notebook("app", in: tmp))
        project.reloadNotebook(frontmatter: true, records: true)
        #expect(project.snapshot.cards.contains { $0.id == "wire-auth" })

        let untouched = invalidates(project.snapshot) {
            project.reloadNotebook(frontmatter: true, records: true)
        }
        #expect(!untouched, "a notebook nobody wrote to leaves the snapshot in place")

        let written = try invalidates(project.snapshot) {
            _ = try NotebookFormat.create(.task, title: "Ship it", in: project.notebookRoot, project: nil)
            project.reloadNotebook(frontmatter: true, records: true)
        }
        #expect(written, "and a new page replaces it, so the check above can fail")
    }

    @Test func aPollThatChangesOneProjectLeavesTheOtherAlone() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = AppModel()
        let first = app.open(try notebook("first", in: tmp))
        let second = app.open(try notebook("second", in: tmp))
        // The fleet screen, where the poll reads every project in full.
        app.reload()

        var secondChanged = false
        let firstChanged = try invalidates((first.snapshot, first.sessions, first.repo, first.reviewDrafts)) {
            secondChanged = try invalidates(second.snapshot) {
                _ = try NotebookFormat.create(.task, title: "Ship it", in: second.notebookRoot, project: nil)
                app.reload()
            }
        }
        #expect(secondChanged, "the poll picked up the new task")
        #expect(!firstChanged, "and nothing a screen of the other project reads was written")
    }

    // `@AppStorage("openProjects")` is a string in defaults; relaunching reads it back.
    @Test func openProjectsRoundTripThroughDefaults() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let suite = "yongkang.test.open.\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let folders = try ["first", "moved", "second"].map { try notebook($0, in: tmp) }

        let app = AppModel()
        for folder in folders { _ = app.open(folder) }
        defaults.set(app.storedProjects, forKey: "openProjects")
        try FileManager.default.removeItem(at: folders[1])

        let relaunched = AppModel()
        relaunched.restore(try #require(defaults.string(forKey: "openProjects")))
        #expect(
            relaunched.projects.map(\.directory.path) == [folders[0].path, folders[2].path],
            "the same folders in the same order, less one that was moved away")
    }
}
