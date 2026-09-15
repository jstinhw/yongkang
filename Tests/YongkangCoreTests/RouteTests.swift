import Foundation
import Testing

@testable import YongkangCore

// Selection has to outlive the 2-second poll, which replaces every card, block and team
// member with a freshly read copy whenever an agent writes a file. A route keeps only the
// ids a re-read gives back, so whatever was selected before the write is found after it.
@Suite struct RouteTests {
    private func writeBlock(_ file: String, in root: URL) throws {
        let blocks = Blocks.root(in: root)
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        try fixture("notebook/c-block-token.md")
            .write(to: blocks.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    @Test func everyNotebookRouteSurvivesAnAgentWrite() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sample = try NotebookLoaderTests.makeSample(in: tmp)
        let root = sample.root
        try writeBlock("github-token.md", in: root)
        Team.seedIfAbsent(root: root)

        let cards = NotebookIndex.load(root: root)
        let project = try #require(cards.first { $0.kind == .project })
        let task = try #require(cards.first { $0.kind == .task })
        let memory = try #require(cards.first { $0.kind == .memory })
        let block = try #require(Blocks.load(root: root).first)
        let member = try #require(Team.load(root: root).last)
        let entry = NotebookEntry.id(for: sample.firstTask)

        // The agent writes one of everything, each sorting ahead of what is selected.
        _ = try NotebookFormat.create(.task, title: "Aaa first", in: root, project: project.id)
        try writeBlock("aaa-first.md", in: root)
        try Team.write(TeamMember(name: "Aaron", skills: ["qa-dev"], owns: "tests"), root: root)

        let reloaded = NotebookIndex.load(root: root)
        #expect(Route.project(project.id).card(in: reloaded)?.url == project.url)
        #expect(Route.task(task.id).card(in: reloaded)?.url == task.url)
        #expect(Route.page(memory.id).card(in: reloaded)?.url == memory.url)
        #expect(Blocks.load(root: root).first { Route.block($0.id) == .block(block.id) }?.url == block.url)
        #expect(Team.load(root: root).first { Route.member($0.name) == .member(member.name) } == member)
        #expect(NotebookLoader.find(entry, in: NotebookLoader.load(root: root))?.title == "wire-auth")
    }

    @Test func onlyNotebookPagesAreCards() {
        let task = NotebookCard(
            id: "wire-auth", url: URL(fileURLWithPath: "/n/tasks/wire-auth.md"), kind: .task,
            title: "Wire auth", status: "todo", project: nil, dependsOn: [])
        #expect(Route.task("wire-auth").card(in: [task]) == task)
        #expect(
            Route.block("wire-auth").card(in: [task]) == nil && Route.member("wire-auth").card(in: [task]) == nil,
            "a block or a teammate that shares a card's id is still not that card")
        // Under string tags a task's review page needed a prefix of its own so it could not
        // read as a file path under `review:`. As cases they differ whatever they hold.
        #expect(Route.review(file: "wire-auth") != .reviewTask("wire-auth"))
    }
}
