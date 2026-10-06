import Foundation
import Testing

@testable import YongkangCore

/// The messages an agent writes to another project, read back so the app can deliver them. A
/// message that cannot be delivered is dropped here rather than guessed at downstream.
@Suite struct MessagesTests {
    private let sender = "11111111-2222-3333-4444-555555555555"
    private let receiver = "66666666-7777-8888-9999-000000000000"

    /// Writes `text` to `.notebook/messages/<file>` under `project`.
    @discardableResult
    private func write(_ text: String, as file: String, in project: URL) throws -> URL {
        let folder = Messages.root(in: NotebookFormat.root(in: project))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(file)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A message in the shape the project's memory fixes, with `fields` in its frontmatter.
    private func message(_ fields: String, body: String = "Add a `/health` route.") -> String {
        "---\nkind: message\n\(fields)\ncreated: 2026-10-06T10:00:00Z\n---\n\n\(body)\n"
    }

    private func load(_ project: URL) -> [ProjectMessage] {
        Messages.load(root: NotebookFormat.root(in: project))
    }

    @Test func noMessagesNoFolder() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(load(tmp).isEmpty, "nothing written to another project, no messages folder")
    }

    @Test func aFirstMessageGoesToProduct() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = try write(
            message(
                """
                to: "../site"
                session: \(sender)
                reply_to: ""
                title: "Health route"
                """),
            as: "health-route.md", in: tmp)

        let read = try #require(load(tmp).first)
        #expect(read.to == "../site")
        #expect(read.session == UUID(uuidString: sender))
        #expect(read.replyTo == nil, "an empty reply_to, quoted as the prompt writes it, is a first message")
        #expect(read.title == "Health route")
        #expect(read.body == "Add a `/health` route.")
        #expect(read.id == NotebookEntry.id(for: url), "the file it came from, symlinks resolved")
    }

    @Test func aReplyNamesTheSessionItAnswers() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(
            message(
                """
                to: "../app"
                session: \(receiver)
                reply_to: \(sender)
                title: "Filed it"
                """, body: "Filed `add-health-route` on our board."),
            as: "filed-it.md", in: tmp)

        let read = try #require(load(tmp).first)
        #expect(read.session == UUID(uuidString: receiver))
        #expect(read.replyTo == UUID(uuidString: sender))
        #expect(read.body == "Filed `add-health-route` on our board.")
    }

    @Test func aQuotedTitleWithAColonReadsWhole() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(message("to: ../site\nsession: \(sender)\ntitle: \"Re: the health route\""), as: "re.md", in: tmp)
        #expect(load(tmp).first?.title == "Re: the health route")
    }

    @Test func anUntitledMessageFallsBackToItsSlug() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(message("to: ../site\nsession: \(sender)\ntitle: \"\""), as: "health-route.md", in: tmp)
        #expect(load(tmp).first?.title == "health-route")
    }

    @Test(arguments: [
        ("no to", "session: 11111111-2222-3333-4444-555555555555"),
        ("empty to", "to: \"\"\nsession: 11111111-2222-3333-4444-555555555555"),
        ("no session", "to: ../site"),
        ("session not a UUID", "to: ../site\nsession: product"),
        ("reply_to not a UUID", "to: ../site\nsession: 11111111-2222-3333-4444-555555555555\nreply_to: product"),
    ])
    func aMalformedMessageIsSkipped(_ name: String, _ fields: String) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(message(fields), as: "bad.md", in: tmp)
        try write(message("to: ../site\nsession: \(sender)\ntitle: Good"), as: "good.md", in: tmp)
        #expect(load(tmp).map(\.title) == ["Good"], "\(name): skipped, and the good one still reads")
    }

    @Test func aFileWithNoFrontmatterIsSkipped() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write("Please add a health route.", as: "loose.md", in: tmp)
        try write("to: ../site", as: "notes.txt", in: tmp)
        #expect(load(tmp).isEmpty)
    }

    /// A write to `messages/` is news to the poll the way a write to `blocks/` is.
    @Test func aWrittenMessageReachesTheSnapshot() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let directory = tmp.appendingPathComponent("app")
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: NotebookFormat.root(in: directory), project: nil)
        let reader = ProjectReader(directory: directory)
        let first = try #require(await reader.notebook(after: NotebookSnapshot(), frontmatter: true, records: true))
        #expect(first.messages.isEmpty)

        try write(message("to: ../site\nsession: \(sender)\ntitle: Health route"), as: "health.md", in: directory)
        let second = try #require(
            await reader.notebook(after: first, frontmatter: true, records: true), "a new message is news")
        #expect(second.messages.map(\.title) == ["Health route"])

        let cheap = second.reread(root: NotebookFormat.root(in: directory), frontmatter: false, records: false)
        #expect(cheap.messages == second.messages, "a cheap read keeps the messages it skips")
    }
}
