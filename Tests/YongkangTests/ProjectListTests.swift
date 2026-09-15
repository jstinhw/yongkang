import Foundation
import Testing
@testable import Yongkang

@Suite struct ProjectListTests {
    /// A project with its memory, two tasks and a run record, a hand-written task filed under
    /// it, and a roadmap page with no frontmatter that belongs to nobody.
    private struct Sample {
        let root: URL
        let project: URL
        let firstTask: URL
        let run: URL
        let cards: [NotebookCard]
    }

    private func sample(in tmp: URL) throws -> Sample {
        let root = NotebookFormat.root(in: tmp)
        let project = try NotebookFormat.create(.project, title: "Launch Beta", in: root,
                                                project: nil, roadmap: "ship-beta")
        _ = try NotebookFormat.create(.memory, title: "Chose SQLite", in: root, project: "launch-beta")
        let first = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        let run = try NotebookFormat.create(.run, title: "Auth partially wired", in: root,
                                            project: "launch-beta", subject: "wire-auth")
        try fixture("notebook/c-tricky-task.md")
            .write(to: root.appendingPathComponent("tasks/tricky.md"), atomically: true, encoding: .utf8)
        try "just notes\n".write(to: root.appendingPathComponent("roadmap/bare.md"), atomically: true, encoding: .utf8)
        return Sample(root: root, project: project, firstTask: first, run: run, cards: NotebookIndex.load(root: root))
    }

    // Paths through the temp dir come back with /private resolved; compare like for like.
    private func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    // Removing a project takes its tasks with it, and nothing else.
    @Test func projectOwnsItsFolderAndTasks() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let notebook = try sample(in: tmp)
        let launch = try #require(notebook.cards.first { $0.id == "launch-beta" })
        let tricky = try #require(notebook.cards.first { $0.id == "tricky" })

        let owned = Set(NotebookFormat.owned(by: launch, in: notebook.cards).map(resolved))
        #expect(owned.contains(resolved(notebook.project.deletingLastPathComponent())),
                "a project is its folder, not just project.md")
        #expect(owned.contains(resolved(notebook.firstTask)) && owned.contains(resolved(tricky.url)),
                "a project's tasks go with it")
        #expect(!owned.contains(resolved(notebook.run)), "run history is not the project's to delete")
        #expect(NotebookFormat.owned(by: tricky, in: notebook.cards) == [tricky.url], "a task is one file")
    }

    // `remove` trashes rather than erases, so this leaves the removed pages in the user's
    // Trash (under a yongkang-test-… temp path), exactly as the self-test did.
    @Test func removingAProjectLeavesRunHistoryAndTheRest() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let notebook = try sample(in: tmp)
        let launch = try #require(notebook.cards.first { $0.id == "launch-beta" })

        try NotebookFormat.remove(launch, in: notebook.cards)
        let left = NotebookIndex.load(root: notebook.root)
        // Run history is an append-only log of what agents did, and is not navigable, so
        // it stays behind; every page a user can still open goes.
        #expect(!left.contains { $0.id == "launch-beta" || ($0.kind != .run && $0.project == "launch-beta") },
                "a page is left filed under a removed project")
        #expect(left.contains { $0.id == "bare" }, "and the rest of the notebook stays")
    }

    // The open-project list lives in defaults, where anything could be sitting. Encoding and
    // decoding are pure: nothing here reads or writes UserDefaults.
    @Test func openProjectsSurviveWhateverIsInDefaults() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let paths = ["/a/b", "/quote\"path", "/a b/c", tmp.path]
        #expect(OpenProjects.decode(OpenProjects.encode(paths)) == paths)
        #expect(OpenProjects.decode("").isEmpty)
        #expect(OpenProjects.decode("{\"not\": \"a list\"}").isEmpty)
    }
}
