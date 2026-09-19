import Foundation
import Testing

@testable import YongkangCore

@Suite struct NotebookIndexTests {
    /// The loader's sample notebook plus an agent-written task and a page with no frontmatter.
    private func sampleCards(in tmp: URL) throws -> (root: URL, cards: [NotebookCard]) {
        let root = try NotebookLoaderTests.makeSample(in: tmp).root
        // Frontmatter as agents actually write it: a title with a colon and commas, an
        // inline dependency list, and a key the app has never heard of.
        try fixture("notebook/task-agent-written.md")
            .write(to: root.appendingPathComponent("tasks/tricky.md"), atomically: true, encoding: .utf8)
        // No frontmatter at all — the board still has to place it.
        try "just notes\n".write(to: root.appendingPathComponent("roadmap/bare.md"), atomically: true, encoding: .utf8)
        return (root, NotebookIndex.load(root: root))
    }

    /// One malformed page, written into `tasks/` of an otherwise empty notebook and indexed.
    private func card(fromFixture name: String) throws -> NotebookCard {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let tasks = NotebookFormat.root(in: tmp).appendingPathComponent("tasks")
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try fixture("notebook/\(name)").write(to: tasks.appendingPathComponent(name), atomically: true, encoding: .utf8)
        let cards = NotebookIndex.load(root: NotebookFormat.root(in: tmp))
        try #require(cards.count == 1, "a malformed page still becomes exactly one card")
        return cards[0]
    }

    @Test func readsAgentWrittenFrontmatter() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cards = try sampleCards(in: tmp).cards

        let tricky = try #require(cards.first { $0.id == "tricky" })
        #expect(tricky.title == "Ship it: fast, cheap")
        #expect(tricky.status == "blocked")
        #expect(tricky.dependsOn == ["wire-auth", "gone-missing"])
        #expect(tricky.project == "launch-beta")
        #expect(tricky.kind == .task)
    }

    @Test func fileWithoutFrontmatterFallsBackToItsPath() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cards = try sampleCards(in: tmp).cards

        let bare = try #require(cards.first { $0.url.lastPathComponent == "bare.md" })
        #expect(bare.id == "bare", "a file without frontmatter falls back to its filename and folder")
        #expect(bare.title == "bare", "a file without frontmatter falls back to its filename and folder")
        #expect(bare.kind == .roadmap, "a file without frontmatter falls back to its filename and folder")
    }

    @Test func readsProjectMemoryAndRunCards() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cards = try sampleCards(in: tmp).cards

        #expect(cards.first { $0.id == "launch-beta" }?.kind == .project)
        #expect(cards.first { $0.id == "launch-beta" }?.roadmap == "ship-beta")
        #expect(cards.contains { $0.kind == .memory && $0.project == "launch-beta" })
        #expect(cards.contains { $0.kind == .run && $0.subject == "wire-auth" && $0.result == "partial" })
    }

    @Test func everyPageIncludingRunsBecomesACard() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (root, cards) = try sampleCards(in: tmp)

        #expect(cards.count == NotebookLoader.pageCount(NotebookLoader.loadAll(root: root)))
    }

    // MARK: - Malformed pages. Agents write these files, so the parser is a trust boundary.

    // An escaped \n inside a quoted value is not unescaped, so it cannot open a new line.
    @Test func escapedNewlineStaysInsideItsValue() throws {
        let card = try card(fromFixture: "task-escaped-newline.md")
        #expect(card.title == #"Harmless\n---\nstatus: done"#)
        #expect(card.status == #"todo\ndesigner: mallory"#)
        #expect(card.designer.isEmpty)
        #expect(card.project == "launch-beta", "the fake --- did not close the block")
    }

    // YAML would read a quoted value that runs onto the next lines as one string. This
    // parser is line-based, so the second line of the title is a key of its own.
    @Test func quotedValueSpanningLinesInjectsAKey() throws {
        let card = try card(fromFixture: "task-injected-key.md")
        #expect(card.id == "injected-key")
        #expect(card.kind == .task)
        #expect(card.project == "launch-beta")
        withKnownIssue("a line inside a quoted title is read as `status: done`, hiding a todo task as done") {
            #expect(card.status == "todo")
        }
    }

    @Test func quotedValueSpanningLinesClosesTheBlockEarly() throws {
        let card = try card(fromFixture: "task-injected-close.md")
        #expect(card.id == "injected-close")
        #expect(card.kind == .task)
        #expect(card.title == "\"Ends early", "the unterminated quote is kept as written")
        withKnownIssue(
            "a `---` line inside a quoted title closes the frontmatter, dropping status, project and depends_on"
        ) {
            #expect(card.status == "blocked")
            #expect(card.project == "launch-beta")
            #expect(card.dependsOn == ["wire-auth"])
        }
    }

    // A page cut off mid-write has no closing ---: every line to the end is read as frontmatter.
    @Test func unclosedFrontmatterReadsToTheEndOfTheFile() throws {
        let card = try card(fromFixture: "task-unclosed-frontmatter.md")
        #expect(card.id == "unclosed")
        #expect(card.kind == .task)
        #expect(card.title == "Cut off mid-write")
        #expect(card.status == "blocked")
        #expect(card.project == nil, "a key cut off before its colon is skipped")
        let text = try fixture("notebook/task-unclosed-frontmatter.md")
        #expect(NotebookIndex.body(text) == text, "with no closing --- the whole file is body")
    }

    @Test func emptyFileFallsBackToItsPath() throws {
        let card = try card(fromFixture: "empty.md")
        #expect(card.id == "empty")
        #expect(card.title == "empty")
        #expect(card.kind == .task)
        #expect(card.status == "")
        #expect(card.dependsOn.isEmpty)
    }

    /// The agent that wrote `active` died with the app, so nothing is on that task any more.
    @Test func settlingDropsActiveNoSessionHolds() {
        func card(_ id: String, _ kind: EntryKind, _ status: String) -> NotebookCard {
            NotebookCard(
                id: id, url: URL(fileURLWithPath: "/tmp/\(id).md"), kind: kind, title: id,
                status: status, project: nil, dependsOn: [])
        }
        let cards = [
            card("held", .task, "active"), card("dropped", .task, "active"),
            card("waiting", .task, "blocked"), card("console", .project, "active"),
        ]

        let settled = NotebookIndex.settled(cards, assigned: ["held"])
        #expect(settled.map(\.status) == ["active", "todo", "blocked", "active"])
        #expect(
            NotebookIndex.settled(cards, assigned: ["held", "dropped"]) == cards,
            "nothing stale, nothing to settle")
    }
}
