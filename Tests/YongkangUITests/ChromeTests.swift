import Foundation
import SwiftUI
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// What the window is made of now: the window's own title bar holding what the custom top bar
/// used to draw. The containers are the system's, so what is left to check here is the state
/// the app still owns — the two strings the title bar shows. The list column's collapse is one
/// `if` on a stored bool, with nothing of its own to test.
@Suite @MainActor struct ChromeTests {
    // MARK: - What the title bar says

    /// The custom bar drew crumbs then a name; the title bar draws the name on its title line
    /// and the crumb under it. Same two strings, so the same screens read the same way.
    @Test func theTitleBarNamesTheScreenAndTheProject() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let directory = tmp.appendingPathComponent("app")
        _ = try NotebookFormat.create(
            .task, title: "Show all agents", in: NotebookFormat.root(in: directory), project: nil)
        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)

        let model = AppModel()
        let view = RootView(model: model)

        model.section = .board
        #expect(view.title(for: project) == "Board", "nothing scoped, so the section names itself")
        #expect(view.subtitle(for: project) == project.name)
        let card = try #require(project.snapshot.cards.first { $0.kind == .task })
        model.selection = .task(card.id)
        #expect(view.title(for: project) == card.title, "what is open is more specific than the section")

        model.section = .agents
        model.selection = .review(file: nil)
        #expect(view.title(for: project) == "Review changes", "the working tree, under Agents")
        #expect(
            view.subtitle(for: project) == (project.repo.branch ?? project.name),
            "it says which branch the changes are on, which is what you commit against")
    }
}
