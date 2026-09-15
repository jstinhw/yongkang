import Foundation
import Testing
@testable import Yongkang

@Suite struct NotebookFormatTests {
    @Test(arguments: [
        ("Ship  the *Beta*! v2", "ship-the-beta-v2"),
        ("///", ""),
    ])
    func slug(title: String, expected: String) {
        #expect(NotebookFormat.slug(title) == expected)
    }

    @Test func rootIsTheDotNotebookFolder() {
        #expect(NotebookFormat.root(in: URL(fileURLWithPath: "/project")).lastPathComponent == ".notebook")
    }

    @Test func firstProjectScaffoldsTheNotebook() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = NotebookFormat.root(in: tmp)

        let project = try NotebookFormat.create(.project, title: "Launch Beta", in: root,
                                                project: nil, roadmap: "ship-beta")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("NOTEBOOK.md").path),
                "the first entry scaffolds the notebook")
        #expect(project.path.hasSuffix("projects/launch-beta/project.md"))
        let text = try String(contentsOf: project, encoding: .utf8)
        #expect(text.contains("id: launch-beta"))
        #expect(text.contains("roadmap: ship-beta"))
    }

    @Test func memoryLivesInItsProject() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = NotebookFormat.root(in: tmp)

        let memory = try NotebookFormat.create(.memory, title: "Chose SQLite", in: root, project: "launch-beta")
        #expect(memory.path.contains("projects/launch-beta/memory/"))
        #expect(memory.lastPathComponent.hasSuffix("-chose-sqlite.md"))
        let text = try String(contentsOf: memory, encoding: .utf8)
        for field in ["subject: launch-beta", "memory_type: note", "source: user", "supersedes: []"] {
            #expect(text.contains(field), "memory frontmatter missing \(field)")
        }
    }

    @Test func memoryNeedsAProject() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: NotebookError.missingProject, "memory needs a project") {
            try NotebookFormat.create(.memory, title: "Orphan", in: NotebookFormat.root(in: tmp), project: nil)
        }
    }

    @Test func sameTaskTitleDoesNotClobber() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = NotebookFormat.root(in: tmp)

        let first = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        let second = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        #expect(first != second, "same title must not clobber an existing task")
        let task = try String(contentsOf: first, encoding: .utf8)
        for field in ["id: wire-auth", "kind: task", "title: \"Wire auth\"", "status: todo",
                      "project: launch-beta", "depends_on: []", "external: {}"] {
            #expect(task.contains(field), "task frontmatter missing \(field)")
        }
    }

    @Test func runRecordsItsSubject() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let run = try NotebookFormat.create(.run, title: "Auth partially wired", in: NotebookFormat.root(in: tmp),
                                            project: "launch-beta", subject: "wire-auth")
        let text = try String(contentsOf: run, encoding: .utf8)
        for field in ["kind: run", "project: launch-beta", "subject: wire-auth", "result: partial"] {
            #expect(text.contains(field), "run frontmatter missing \(field)")
        }
    }

    // The agent copies paths straight out of the layout block. Every one has to be
    // anchored to .notebook/, or it creates roadmap/ and tasks/ at the project root.
    @Test(arguments: NotebookFormat.folders)
    func specAnchorsLayoutPaths(folder: String) {
        #expect(NotebookFormat.specText.contains(".notebook/\(folder)/"),
                "\(folder) is not anchored to .notebook/ in the spec")
        #expect(!NotebookFormat.specText.contains("\n    \(folder)/"),
                "\(folder) still appears as a bare project-root path in the spec")
    }

    // The app writes the title into frontmatter that NotebookIndex reads line by line, so a
    // line break in a title must not become a key of its own or close the block early.
    @Test(arguments: ["Wire auth\ndesigner: mallory", "Wire auth\n---\nstatus: done"])
    func titleWithNewlineStaysOneValue(title: String) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = try NotebookFormat.create(.task, title: title, in: NotebookFormat.root(in: tmp),
                                            project: "launch-beta")
        let card = try #require(NotebookIndex.card(at: url))
        #expect(card.id == NotebookFormat.slug(title), "keys written before the title are untouched")
        #expect(card.kind == .task, "keys written before the title are untouched")
        withKnownIssue("NotebookFormat.yaml escapes quotes and backslashes but not newlines") {
            #expect(card.title == title)
            #expect(card.status == "todo")
            #expect(card.designer.isEmpty)
        }
    }
}
