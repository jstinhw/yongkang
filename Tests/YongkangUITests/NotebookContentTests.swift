import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

@Suite struct NotebookContentTests {
    // A project or task page is parsed into structured content, not shown as raw
    // Markdown — real pages restate the title as `# `, put a checklist right after
    // the intro with no heading of its own, and wrap a checklist item's text onto a
    // continuation line with no bullet.
    @Test func bodyWithoutFrontmatterIsTheWholeText() {
        #expect(NotebookIndex.body("no frontmatter here") == "no frontmatter here")
    }

    @Test func realProjectPageParsesIntoSections() throws {
        let content = NotebookContent.sections(try fixture("notebook/c-project-page.md"))
        try #require(
            content.map(\.heading) == [nil, "Blocked on accounts", "Tasks"],
            "the `# ` title restates the frontmatter and is dropped, not shown as a section")
        let intro: [NotebookContent.Block] = [
            .paragraph("Intro line one intro line two."),
            .checklist([
                .init(text: "done item", done: true),
                .init(text: "open item that wraps onto a continuation line", done: false),
            ]),
        ]
        #expect(
            content[0].blocks == intro,
            "a wrapped checklist line folds into the item it continues, not a stray paragraph")
        #expect(content[1].blocks == [NotebookContent.Block.paragraph("Stays `todo` on purpose.")])
        #expect(content[2].blocks == [NotebookContent.Block.list(["[[a]]", "[[b]] — annotated, so it stays"])])
    }

    @Test func memoryPageKeepsProceduresAndCode() {
        let rich = NotebookContent.sections(
            """
            ## Steps

            1. Open settings
            2. Save the value

                select * from todos;

            ```sh
            npm test
            ```
            """)
        let expected: [NotebookContent.Block] = [
            .numberedList(["Open settings", "Save the value"]),
            .code("select * from todos;"),
            .code("npm test"),
        ]
        #expect(rich.first?.blocks == expected, "memory pages keep numbered procedures and code readable")
    }

    // Cross-links: a bare `[[id]]` list item is a pure reference; one with trailing
    // prose is not, even though it still contains a link.
    @Test func crossLinks() {
        #expect(NotebookContent.wikilinks(in: "See [[a]] and [[b]] too") == ["a", "b"])
        #expect(NotebookContent.isPureLinks("[[a]]"))
        #expect(!NotebookContent.isPureLinks("[[a]] — why it matters"))
        #expect(!NotebookContent.isPureLinks("no link here"))
        #expect(
            NotebookContent.tokens("open [[x") == [.text("open "), .text("[[x")],
            "an unmatched [[ is kept as plain text")
    }

    // Links are agent-written. The page resolves one by matching a card's id and never
    // opens it as a path, so `../` inside one is just an id nothing answers to.
    @Test func linkWithDotDotIsOnlyAnID() {
        #expect(
            NotebookContent.tokens("see [[../../etc/passwd]]")
                == [.text("see "), .link("../../etc/passwd")],
            "a link is kept verbatim as an id, never normalised into a path")
        #expect(NotebookContent.isPureLinks("[[../tasks/a]]"))
    }

    // A newline cannot survive inside a link on a real page: the page is split into lines
    // before links are read. Only a caller handing `tokens` raw text would see one.
    @Test func linkBrokenAcrossLines() {
        #expect(
            NotebookContent.tokens("[[a\nb]]") == [.link("a\nb")],
            "tokens alone does not treat a newline specially")
        let wrapped = NotebookContent.sections("- [[a\n  b]]")
        #expect(
            wrapped.first?.blocks == [NotebookContent.Block.list(["[[a b]]"])],
            "a link wrapped onto a continuation line folds into one id with a space")
        let split = NotebookContent.sections("[[a\n\nb]]")
        #expect(
            split.first?.blocks == [NotebookContent.Block.paragraph("[[a"), .paragraph("b]]")],
            "a blank line in the middle leaves two unmatched halves")
        #expect(
            split.flatMap(\.blocks).allSatisfy { block in
                guard case .paragraph(let text) = block else { return false }
                return NotebookContent.wikilinks(in: text).isEmpty
            }, "and neither half is a link")
    }

    // The board holds one kind of card now — every task is a candidate for the same
    // batch — so picking is a plain toggle.
    @Test @MainActor func pickingIsAToggle() {
        let tricky = NotebookCard(
            id: "tricky", url: URL(fileURLWithPath: "/tasks/tricky.md"), kind: .task,
            title: "Ship it: fast, cheap", status: "blocked", project: "launch-beta",
            dependsOn: ["wire-auth", "gone-missing"])
        #expect(
            NotebookBoard.picking(tricky, from: ["bare"]) == ["bare", "tricky"],
            "a card click adds itself to the batch")
        #expect(
            NotebookBoard.picking(tricky, from: ["bare", "tricky"]) == ["bare"],
            "clicking it again takes it out")
    }

    @Test @MainActor func editorConflict() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let page = tmp.appendingPathComponent("page.md")
        try "agent".write(to: page, atomically: true, encoding: .utf8)

        #expect(
            NotebookEditor.save("mine", over: "loaded before the agent", to: page)?.title
                == "This page changed while you were editing")
        #expect(
            try String(contentsOf: page, encoding: .utf8) == "agent",
            "an agent edit must not be overwritten by a stale editor")
        #expect(NotebookEditor.save("mine", over: "agent", to: page) == nil)
        #expect(try String(contentsOf: page, encoding: .utf8) == "mine")
        #expect(
            NotebookEditor.save("mine", over: "", to: tmp.appendingPathComponent("gone.md")) != nil,
            "a page that can't be read says why rather than saving")
    }
}
