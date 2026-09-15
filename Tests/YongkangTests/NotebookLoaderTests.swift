import Foundation
import Testing

@testable import Yongkang

@Suite struct NotebookLoaderTests {
    struct Sample {
        let root: URL
        let project: URL
        let firstTask: URL
        let run: URL
    }

    /// The notebook the self-test built up step by step: one project with a memory, two
    /// tasks with the same title, and one run record. `NotebookIndexTests` builds on it too.
    static func makeSample(in tmp: URL) throws -> Sample {
        let root = NotebookFormat.root(in: tmp)
        let project = try NotebookFormat.create(
            .project, title: "Launch Beta", in: root,
            project: nil, roadmap: "ship-beta")
        _ = try NotebookFormat.create(.memory, title: "Chose SQLite", in: root, project: "launch-beta")
        let firstTask = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        let run = try NotebookFormat.create(
            .run, title: "Auth partially wired", in: root,
            project: "launch-beta", subject: "wire-auth")
        return Sample(root: root, project: project, firstTask: firstTask, run: run)
    }

    /// Pages an agent could plausibly write badly. Loading must still list each one.
    static let malformedFixtures = [
        "empty.md", "task-unclosed-frontmatter.md", "task-injected-key.md",
        "task-injected-close.md", "task-escaped-newline.md",
    ]

    @Test func missingNotebookReadsAsEmpty() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = tmp.appendingPathComponent("project")

        #expect(
            NotebookLoader.load(root: NotebookFormat.root(in: project)).isEmpty,
            "a project with no .notebook reads as empty")
        #expect(!FileManager.default.fileExists(atPath: project.path), "and nothing is written to the project folder")
    }

    @Test func treeShowsHumanFoldersAndHidesRuns() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sample = try Self.makeSample(in: tmp)

        let tree = NotebookLoader.load(root: sample.root)
        #expect(tree.map(\.title) == ["roadmap", "projects", "tasks"])
        #expect(
            NotebookLoader.find(NotebookEntry.id(for: sample.run), in: tree) == nil,
            "run history stays out of human notebook navigation")
        #expect(NotebookLoader.find(NotebookEntry.id(for: sample.firstTask), in: tree)?.title == "wire-auth")
    }

    @Test func projectRowOpensItsOwnPage() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sample = try Self.makeSample(in: tmp)

        let projectRow = try #require(
            NotebookLoader.load(root: sample.root)
                .first { $0.title == "projects" }?.children?.first)
        #expect(projectRow.title == "launch-beta")
        #expect(projectRow.url.lastPathComponent == "project.md", "a project row opens its own page")
        #expect(
            projectRow.id == NotebookEntry.id(for: sample.project.deletingLastPathComponent()),
            "add(.project) selects the folder row by this id")
        #expect(projectRow.children?.map(\.title) == ["memory"])

        // Icons come from the path, and memory sits under projects/ — it must win.
        #expect(projectRow.icon == NotebookLoader.icon(forFolder: "projects"))
        let memoryPages = try #require(projectRow.children?.first?.children)
        #expect(memoryPages.first?.icon == "brain")
        #expect(memoryPages.count == 1)
    }

    @Test func showCompletedTogglesDoneRows() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sample = try Self.makeSample(in: tmp)
        let tree = NotebookLoader.load(root: sample.root)
        let projectRowID = NotebookEntry.id(for: sample.project.deletingLastPathComponent())
        let doneRows = [
            NotebookCard(
                id: "launch-beta", url: sample.project, kind: .project, title: "Launch Beta",
                status: "done", project: nil, dependsOn: []),
            NotebookCard(
                id: "wire-auth", url: sample.firstTask, kind: .task, title: "Wire auth",
                status: "done", project: "launch-beta", dependsOn: []),
        ]

        let unfinishedTree = NotebookLoader.display(tree, cards: doneRows, showDone: false)
        #expect(NotebookLoader.find(projectRowID, in: unfinishedTree) == nil)
        #expect(NotebookLoader.find(NotebookEntry.id(for: sample.firstTask), in: unfinishedTree) == nil)
        #expect(
            NotebookLoader.find(
                projectRowID,
                in: NotebookLoader.display(tree, cards: doneRows, showDone: true)) != nil,
            "Show Completed restores done project and task rows")
    }

    @Test func pageCountSkipsRunsAndBareFolders() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sample = try Self.makeSample(in: tmp)

        // project.md + one memory + two tasks; runs and bare folders are not shown.
        #expect(NotebookLoader.pageCount(NotebookLoader.load(root: sample.root)) == 4)
    }

    // The loader only reads names, never contents, so a broken page is still a row to open.
    @Test(arguments: malformedFixtures)
    func malformedPageStillListsAsATaskRow(name: String) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let tasks = NotebookFormat.root(in: tmp).appendingPathComponent("tasks")
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try fixture("notebook/\(name)").write(to: tasks.appendingPathComponent(name), atomically: true, encoding: .utf8)

        let tree = NotebookLoader.load(root: NotebookFormat.root(in: tmp))
        let row = try #require(tree.first { $0.title == "tasks" }?.children?.first)
        #expect(row.title == (name as NSString).deletingPathExtension)
        #expect(row.icon == NotebookLoader.icon(forFolder: "tasks"))
        #expect(NotebookLoader.pageCount(tree) == 1)
    }
}
