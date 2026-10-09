import Foundation
import Testing

@testable import YongkangCore

@Suite struct BlocksTests {
    /// The session every block fixture names as the lead waiting on it.
    private let leadID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// Writes `Fixtures/notebook/<fixture>` to `.notebook/blocks/<file>` under `project`.
    @discardableResult
    private func writeBlock(_ fixtureName: String, as file: String, in project: URL) throws -> URL {
        let blocks = Blocks.root(in: NotebookFormat.root(in: project))
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        let url = blocks.appendingPathComponent(file)
        try fixture("notebook/\(fixtureName)").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// One `UserBlock` built by hand, so the body under test is exactly the body written here.
    private func made(kind: String = "block", body: String) -> UserBlock {
        UserBlock(
            id: "b", url: URL(fileURLWithPath: "/tmp/b.md"), slug: "b", title: "Needs a key",
            status: "open", kind: kind, stage: "ready", session: nil, action: "", link: nil,
            task: nil, resolution: "", body: body, before: nil, branch: "", revisions: [])
    }

    @Test func theUsersHalfOfABlockStopsAtTheProcedure() {
        let block = made(
            body: """
                The deploy cannot go out until Vercel will take it from CI.

                ## Needed from you

                - A token scoped to the project.

                ## Steps

                1. Open the token page and create one scoped to this project.
                2. Set PROJECT_URL in CI from the linked project.
                """)
        #expect(
            block.brief == """
                The deploy cannot go out until Vercel will take it from CI.

                ## Needed from you

                - A token scoped to the project.
                """,
            "the steps are the engineer's, and never reach the screen the user opened")
    }

    @Test func aBlockWithNoProcedureKeepsItsWholeBody() {
        #expect(made(body: "Paste the key.").brief == "Paste the key.")
    }

    @Test func aProposalKeepsItsWholeBodyEvenWithSteps() {
        let body = "A plan.\n\n## Steps\n\n1. Write the tasks."
        #expect(made(kind: "proposal", body: body).brief == body, "a proposal is read, not followed")
    }

    /// What zsh actually passes to the agent for a given quoted argument.
    private func echo(_ quotedArgument: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf %s \(quotedArgument)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test func noGateNoBlocks() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(Blocks.load(root: NotebookFormat.root(in: tmp)).isEmpty, "no gate hit, no blocks folder")
    }

    // A block, exactly as the engineering-lead skill writes one, and the loop it opens:
    // read it back, hand it to a session, resolve it, tell the waiting lead.
    @Test func blockReadsBackAndReachesTheFDE() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try writeBlock("c-block-token.md", as: "github-token.md", in: tmp)

        let block = try #require(Blocks.load(root: NotebookFormat.root(in: tmp)).first)
        #expect(block.waiting && block.session == leadID && block.task == "wire-auth")
        #expect(block.link?.host == "github.com", "the page the user has to be on")
        #expect(block.body.contains("Generate the token"), "the checklist is what the user reads")
        #expect(
            block.body.contains("Authenticate the GitHub MCP"),
            "the procedure rides along for the agent to deliver one step at a time")
        let guide = NotebookFormat.unblockPrompt(block: block)
        #expect(
            guide.contains(".notebook/blocks/github-token.md") && guide.contains("`status: done`"),
            "the guiding session is pointed at the file it flips to done")
        #expect(
            guide.contains("go and read what you need yourself"),
            "and told that my half ends at signing in — a value on a page is its to fetch")
        #expect(
            guide.contains("do not ask me to say it is done: poll for it"),
            "a step it can check from the shell, it watches for instead of waiting on me")
        let echoed = try echo(AgentCommand.quoted(guide))
        #expect(echoed == guide, "block prompt mangled by the shell")
    }

    @Test func resolvingIsOneFrontmatterEdit() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try writeBlock("c-block-token.md", as: "github-token.md", in: tmp)
        let root = NotebookFormat.root(in: tmp)
        let block = try #require(Blocks.load(root: root).first)

        Blocks.resolve(block)
        let cleared = try #require(Blocks.load(root: root).first { $0.id == block.id })
        #expect(!cleared.waiting, "resolving a block is one frontmatter edit")
        #expect(
            cleared.title == block.title && cleared.action == block.action,
            "and touches nothing else in the file")
        #expect(
            NotebookFormat.unblockedMessage(block: cleared).contains(block.title),
            "the waiting lead is told which block cleared")
    }

    // Anything in blocks/ has to reach the user, however badly its frontmatter is written:
    // a missing status reads as open, and a misspelt one is still waiting.
    @Test(arguments: [
        ("c-block-missing-status.md", "open"),
        ("c-block-garbled-status.md", "dnoe  # typo"),
    ])
    func badStatusStillReachesTheUser(_ fixtureName: String, _ status: String) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try writeBlock(fixtureName, as: "gate.md", in: tmp)

        let block = try #require(Blocks.load(root: NotebookFormat.root(in: tmp)).first)
        #expect(block.status == status)
        #expect(block.waiting, "a block written a little wrong still shows up")
        #expect(block.slug == "gate" && !block.title.isEmpty)
    }

    /// How a demo comes back after a quit took its page down: the command the designer wrote.
    @Test func aDemoSaysHowToServeItAgain() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let blocks = Blocks.root(in: NotebookFormat.root(in: tmp))
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        try """
        ---
        kind: demo
        title: "Task page diff"
        url: http://localhost:3101
        serve: npm run dev -- --port 3101
        ---
        """.write(to: blocks.appendingPathComponent("diff-demo.md"), atomically: true, encoding: .utf8)
        try "---\nkind: demo\nurl: https://example.com/canvas\n---\n"
            .write(to: blocks.appendingPathComponent("page-demo.md"), atomically: true, encoding: .utf8)

        let found = Blocks.load(root: NotebookFormat.root(in: tmp))
        #expect(found.first { $0.slug == "diff-demo" }?.serve == "npm run dev -- --port 3101")
        #expect(found.first { $0.slug == "page-demo" }?.serve == "", "a published demo has nothing to start")
    }

    @Test func onlyAPageOnThisMacIsOursToStart() throws {
        #expect(DemoServer.isLocal(try #require(URL(string: "http://localhost:3101"))))
        #expect(DemoServer.isLocal(try #require(URL(string: "http://127.0.0.1:5173/board"))))
        #expect(!DemoServer.isLocal(try #require(URL(string: "https://claude.ai/artifact/abc"))))
    }

    @Test func aPortNothingListensOnDoesNotAnswer() async throws {
        // Port 1 is privileged and never a dev server: refused at once, not timed out.
        #expect(await !DemoServer.answers(try #require(URL(string: "http://127.0.0.1:1"))))
    }

    @Test func garbledFieldsAreDroppedNotTrusted() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try writeBlock("c-block-garbled-status.md", as: "gate.md", in: tmp)
        let root = NotebookFormat.root(in: tmp)
        let block = try #require(Blocks.load(root: root).first)

        #expect(block.session == nil, "a session that is not a UUID routes to the newest lead")
        #expect(block.link == nil, "only an http(s) link is ever opened")
        Blocks.resolve(block)
        #expect(
            try #require(Blocks.load(root: root).first).waiting == false,
            "a misspelt status line is still the line resolving rewrites")
    }

    // Today, resolving matches the literal `status:` line. A block that never had one
    // reads as open, but the button has nothing to rewrite and leaves the file as it was.
    @Test func resolvingABlockWithNoStatusLineChangesNothing() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = try writeBlock("c-block-missing-status.md", as: "gate.md", in: tmp)
        let root = NotebookFormat.root(in: tmp)
        let before = try String(contentsOf: url, encoding: .utf8)

        Blocks.resolve(try #require(Blocks.load(root: root).first))
        #expect(try String(contentsOf: url, encoding: .utf8) == before)
        #expect(try #require(Blocks.load(root: root).first).waiting, "so it stays waiting")
    }
}
