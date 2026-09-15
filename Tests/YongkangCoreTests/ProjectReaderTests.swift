import Foundation
import Testing

@testable import YongkangCore

/// The reader answers with values and says nothing when a read found nothing new. That "nothing
/// new" is what keeps a two-second poll from re-rendering every screen in the window.
@Suite struct ProjectReaderTests {
    /// A folder with a notebook holding one task, and a project card listing one repo.
    private func notebook(in tmp: URL) throws -> URL {
        let directory = tmp.appendingPathComponent("app")
        let root = NotebookFormat.root(in: directory)
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: nil)
        return directory
    }

    @Test func anUnchangedNotebookAnswersWithNothing() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let reader = ProjectReader(directory: try notebook(in: tmp))

        let first = try #require(
            await reader.notebook(after: NotebookSnapshot(), frontmatter: true, records: true),
            "the first read is always news: the snapshot it is compared against is empty")
        #expect(first.cards.contains { $0.id == "wire-auth" })
        #expect(
            await reader.notebook(after: first, frontmatter: true, records: true) == nil,
            "a notebook nobody wrote to is nothing to publish")

        _ = try NotebookFormat.create(
            .task, title: "Ship it", in: NotebookFormat.root(in: reader.directory), project: nil)
        let second = try #require(await reader.notebook(after: first, frontmatter: true, records: true))
        #expect(second.cards.count == first.cards.count + 1)
    }

    /// The page's own Markdown rides along with the frontmatter that was parsed out of it, so
    /// nothing downstream opens the file again to draw it.
    @Test func aCardCarriesItsPageText() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let directory = try notebook(in: tmp)
        let reader = ProjectReader(directory: directory)
        let card = try #require(
            await reader.notebook(after: NotebookSnapshot(), frontmatter: true, records: true)?
                .cards.first { $0.id == "wire-auth" })
        let file = try String(contentsOf: card.url, encoding: .utf8)

        #expect(card.body == NotebookIndex.body(file))
        #expect(!card.body.contains("---"), "and the frontmatter is not in it")
    }

    /// A project with no `repos:` is its own repo, and a plan says whether the folder is
    /// there and what a front end would be — everything a screen asks, answered once.
    @Test func aPlanAnswersWhatAScreenAsksOfARepo() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let directory = try notebook(in: tmp)
        _ = try NotebookFormat.create(.project, title: "Console", in: NotebookFormat.root(in: directory), project: nil)
        let reader = ProjectReader(directory: directory)
        let cards = try #require(
            await reader.notebook(after: NotebookSnapshot(), frontmatter: true, records: true)?.cards)

        let plans = await Service.plans(for: cards, in: directory)
        let plan = try #require(plans.first)
        #expect(plans.count == 1, "one project card with no repos of its own")
        #expect(plan.card == "console" && plan.repo == directory.lastPathComponent)
        #expect(plan.exists, "the project folder is on disk")
        #expect(plan.services.map(\.frontend) == [false], "no package.json, so nothing to preview")
    }
}
