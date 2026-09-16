import Foundation
import SwiftUI
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// What the window is made of now: a split view whose sidebar holds the list column, and the
/// window's own title bar holding what the custom top bar used to draw. The containers are the
/// system's, so what is left to check here is the state the app still owns — the one bit that
/// says whether the list is collapsed, and the two strings the title bar shows.
@Suite @MainActor struct ChromeTests {
    // MARK: - The list column's collapsed state

    @Test func collapsedStateRoundTripsThroughTheSplitView() {
        #expect(NavigationSplitViewVisibility(listHidden: true) == .detailOnly)
        #expect(NavigationSplitViewVisibility(listHidden: false) == .all)
        #expect(NavigationSplitViewVisibility(listHidden: true).listHidden)
        #expect(!NavigationSplitViewVisibility(listHidden: false).listHidden)
    }

    @Test func anyVisibilityThatShowsTheListReadsAsShowing() {
        // `.doubleColumn` is what SwiftUI hands back when the divider is dragged open in a
        // two-column split view. Only `.detailOnly` means the column is gone.
        #expect(!NavigationSplitViewVisibility.doubleColumn.listHidden)
        #expect(!NavigationSplitViewVisibility.automatic.listHidden)
        #expect(NavigationSplitViewVisibility.detailOnly.listHidden)
    }

    /// ⌘\ moves panes around; it must not reach a running agent. The registry is the only
    /// owner of a PTY (D13), and nothing in the collapsed state touches it.
    @Test func collapsingTheListLeavesEveryTerminalWhereItIs() {
        let registry = TerminalRegistry(shell: ["/bin/sh", "-c"])
        let session = CodeSession(title: "Test", icon: "terminal", line: "sleep 30", agent: .claude)
        registry.start(session)
        let terminal = registry.view(for: session.id)
        #expect(terminal != nil)

        var visibility = NavigationSplitViewVisibility(listHidden: false)
        for hidden in [true, false, true] {
            visibility = NavigationSplitViewVisibility(listHidden: hidden)
            #expect(visibility.listHidden == hidden)
            #expect(
                registry.view(for: session.id) === terminal,
                "the same terminal, still the registry's, whichever way the column is set")
        }
        registry.terminate(session.id)
    }

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

        model.section = .overview
        #expect(view.title(for: project) == "Overview")
        #expect(view.subtitle(for: project) == project.name)

        model.section = .blocks
        #expect(view.title(for: project) == "Blocks")

        model.section = .board
        #expect(view.title(for: project) == "Board", "nothing scoped, so the section names itself")
        let card = try #require(project.snapshot.cards.first { $0.kind == .task })
        model.selection = .task(card.id)
        #expect(view.title(for: project) == card.title, "what is open is more specific than the section")

        model.section = .review
        #expect(
            view.subtitle(for: project) == (project.repo.branch ?? project.name),
            "Review says which branch the changes are on, which is what you approve against")
    }
}
