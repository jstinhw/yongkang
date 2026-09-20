import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The gate that holds design work until the user has seen it: Product's `designer:`
/// field is what marks a task, a `kind: demo` block is what waits on the user, and the
/// board draws full cards only where something is actually happening.
@Suite struct DesignGateTests {

    /// A notebook with a design task ("Hero and download", `designer: Allen`) and a plain one.
    private func makeGate(in dir: URL) throws -> (root: URL, task: URL, plain: URL) {
        let root = NotebookFormat.root(in: dir.appendingPathComponent("gate"))
        let task = try NotebookFormat.create(.task, title: "Hero and download", in: root, project: nil)
        // Into the frontmatter, the way Product writes it — a line under the body is not
        // frontmatter and must not read as one.
        let written = try String(contentsOf: task, encoding: .utf8)
            .replacingOccurrences(of: "\nstatus: todo", with: "\nstatus: todo\ndesigner: Allen")
        try written.write(to: task, atomically: true, encoding: .utf8)
        let plain = try NotebookFormat.create(.task, title: "Connect to Vercel", in: root, project: nil)
        return (root, task, plain)
    }

    @Test func designerFieldMarksDesignWork() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = try makeGate(in: dir)

        let card = try #require(NotebookIndex.card(at: gate.task))
        #expect(card.designer == "Allen", "designer: is read off a task")
        #expect(card.isDesignWork, "a task with a designer is design work")
        let plain = try #require(NotebookIndex.card(at: gate.plain))
        #expect(plain.isDesignWork == false, "and a task without one is not — the app never guesses")
    }

    // Design blocks engineering: the build waits on the design task itself, so it
    // cannot start until the user's approval has finished that task.
    @Test func designTaskHoldsTheBuild() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = try makeGate(in: dir)

        let design = try #require(NotebookIndex.card(at: gate.task))
        let build = NotebookCard(
            id: "build-hero", url: gate.plain, kind: .task,
            title: "Build the hero", status: "todo", project: nil,
            dependsOn: [design.id])
        #expect(
            !NotebookBoard.isReady(build, in: [design, build]),
            "no engineer starts while the design task is open")
        let approved = NotebookCard(
            id: design.id, url: gate.task, kind: .task, title: design.title,
            status: "done", project: nil, dependsOn: [], designer: "Allen")
        #expect(
            NotebookBoard.isReady(build, in: [approved, build]),
            "approving the demo finishes the design task and releases the build")
    }

    // A demo is a block. Everything the gate shows comes off that one file.
    @Test func demoBlockListsEveryRevision() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocks = Blocks.root(in: NotebookFormat.root(in: dir.appendingPathComponent("gate")))
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        let file = blocks.appendingPathComponent("hero-and-download-demo.md")
        try """
        ---
        id: hero-and-download-demo
        kind: demo
        title: "Hero and download"
        status: open
        task: hero-and-download
        branch: demo/hero-and-download
        before: http://localhost:3000
        url: http://localhost:3101
        ---

        ## Revisions

        - v1 · three feature columns · http://localhost:3100
        - v2 · one claim, one button · http://localhost:3101
        - v3 · a pass that was not kept running
        """.write(to: file, atomically: true, encoding: .utf8)

        let demo = try #require(Blocks.block(at: file))
        #expect(demo.isDemo && demo.waiting, "an open demo is waiting on the user")
        #expect(demo.branch == "demo/hero-and-download")
        #expect(demo.before?.absoluteString == "http://localhost:3000")
        try #require(demo.revisions.count == 3, "every pass is listed, not just the last")
        #expect(demo.revisions[0].label == "v1")
        #expect(
            demo.revisions[1].note == "one claim, one button",
            "the note is what is left after the label and the url")
        #expect(demo.revisions[1].url?.absoluteString == "http://localhost:3101")
        #expect(
            demo.revisions[2].url == nil,
            "a pass with no url still counts — its note is the record")
    }

    // Full cards only at the live edge: what could start, and what is held up.
    @Test func readyOnlyAtTheLiveEdge() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = try makeGate(in: dir)
        let file = gate.root.appendingPathComponent("blocks/hero-and-download-demo.md")

        let cards = [
            try #require(NotebookIndex.card(at: gate.plain)),
            NotebookCard(
                id: "done-one", url: file, kind: .task, title: "Scaffold", status: "done",
                project: nil, dependsOn: []),
            NotebookCard(
                id: "next", url: file, kind: .task, title: "Next", status: "todo",
                project: nil, dependsOn: ["done-one"]),
            NotebookCard(
                id: "later", url: file, kind: .task, title: "Later", status: "todo",
                project: nil, dependsOn: ["next"]),
        ]
        #expect(NotebookBoard.isReady(cards[2], in: cards), "its blocker is done")
        #expect(!NotebookBoard.isReady(cards[3], in: cards), "its blocker is not")
        let missing = NotebookCard(
            id: "typo", url: file, kind: .task, title: "Typo",
            status: "todo", project: nil, dependsOn: ["nothing-by-that-id"])
        #expect(
            NotebookBoard.isReady(missing, in: cards),
            "an id that resolves to nothing must not silently freeze a chain")
    }

    // The board used to list only demos, so a gate waiting on a go-ahead was a number in the
    // sidebar and nothing on the board. Both read the same folder now.
    @Test func everyOpenBlockWaitsOnTheUser() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = try makeGate(in: dir)
        let blocks = Blocks.root(in: gate.root)
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        try """
        ---
        id: hero-demo
        kind: demo
        title: "Hero and download"
        status: open
        task: hero-and-download
        ---
        """.write(to: blocks.appendingPathComponent("hero-demo.md"), atomically: true, encoding: .utf8)
        try """
        ---
        id: releases-repo
        kind: block
        title: "Go-ahead to create the releases repo"
        status: open
        task: create-releases-repo
        ---
        """.write(
            to: blocks.appendingPathComponent("releases-repo.md"), atomically: true, encoding: .utf8)

        let open = Blocks.load(root: gate.root).waitingOnUser
        #expect(open.count == 2, "a gate counts the same as a demo")
        let held = try #require(
            open.waiting(on: "create-releases-repo"), "the gate reaches the task it holds")
        #expect(!held.isDemo && BoardInspector.open(held) == "Open block")
        #expect(open.waiting(on: "scaffold-site") == nil, "nothing is waiting on a task with no block")
    }
}
