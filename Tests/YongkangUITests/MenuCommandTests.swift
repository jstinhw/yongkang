import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// A menu item is disabled, never hidden, when the window cannot act on it. Most of those
/// rules are "there is a project open"; the one with a real shape is Agent → Assign to Lead,
/// which is this suite. It reads the same state the menu item does, with no window involved.
@Suite @MainActor struct MenuCommandTests {
    private func project(tasks titles: [String], in tmp: URL) async throws -> ProjectModel {
        let directory = tmp.appendingPathComponent("app")
        for title in titles {
            _ = try NotebookFormat.create(.task, title: title, in: NotebookFormat.root(in: directory), project: nil)
        }
        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)
        return project
    }

    @Test func assignToLeadIsLitOnlyForATaskThatCouldStart() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let model = AppModel()

        model.selection = .task("wire-auth")
        #expect(model.assignableTask == nil, "no project entered: nothing to assign, so the item is dark")

        model.enter(project)
        model.selection = nil
        #expect(model.assignableTask == nil, "a project on its own is not a task")

        model.selection = .board
        #expect(model.assignableTask == nil, "the board's own ticks are the board's, not the menu's")

        model.selection = .task("wire-auth")
        #expect(model.assignableTask?.id == "wire-auth", "the task the window has open is what the item hands over")

        model.selection = .task("gone")
        #expect(model.assignableTask == nil, "a card that is not there cannot be assigned")
    }

    @Test func aTaskAlreadyOutOrAlreadyDoneIsNotAssignableAgain() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth", "Ship it"], in: tmp)
        let model = AppModel()
        model.enter(project)

        // Out with a lead, the way `TaskDetail`'s own button reads it.
        _ = project.addSession(.claude, title: "Engineering Lead", taskIDs: ["wire-auth"])
        model.selection = .task("wire-auth")
        #expect(model.assignableTask == nil, "a lead already has it; a second would do the work twice")

        let shipIt = try #require(project.snapshot.cards.first { $0.id == "ship-it" })
        let done = try String(contentsOf: shipIt.url, encoding: .utf8)
            .replacingOccurrences(of: "status: todo", with: "status: done")
        try done.write(to: shipIt.url, atomically: true, encoding: .utf8)
        await project.reloadNotebook(frontmatter: true, records: true)
        model.selection = .task("ship-it")
        #expect(model.assignableTask == nil, "finished work has nothing left to hand out")
    }

    /// The other items share one rule between them, so it is worth one check that the state
    /// it reads really is empty on the fleet screen and filled inside a project.
    @Test func everyProjectScopedItemIsDarkUntilAProjectIsEntered() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let model = AppModel()
        #expect(model.entered == nil, "the fleet screen: Close Project, Reveal, ⌘1–⌘5, ⌘\\, ⌘[ and Agent are dark")
        model.enter(project)
        #expect(model.entered === project)
        model.leave()
        #expect(model.entered == nil, "Go → All Projects puts it back, and darkens them again")
    }
}
