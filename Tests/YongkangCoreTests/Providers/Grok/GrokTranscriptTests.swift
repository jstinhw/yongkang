import Foundation
import Testing

@testable import YongkangCore

/// `.serialized`: `AgentUsage.samples` keeps a process-global read cursor per file path
/// (`AgentUsage.files`, a plain dictionary). Each test reads its own temporary path, so a
/// cursor left by another test never applies, but the dictionary itself is not safe to
/// write from two tests at once.
@Suite(.serialized) struct GrokTranscriptTests {
    private let sid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    // Grok keeps the readable chat and usage stream beside each other under the UUID
    // Yongkang gives it. Both must resolve from the project path without a scan.
    @Test func sessionFolderPercentEncodesTheProjectPath() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let grokFolder = GrokTranscripts.sessionFolder(
            sessionID: sid,
            projectDirectory: URL(fileURLWithPath: "/a/b c"),
            grokHome: tmp.appendingPathComponent(".grok"))
        #expect(grokFolder.path.hasSuffix("/sessions/%2Fa%2Fb%20c/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    @Test func chatHistoryDropsReasoning() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let grokLog = try sessionFolder(in: tmp).appendingPathComponent("chat_history.jsonl")
        try fixture("grok/grok-chat-history.jsonl").write(to: grokLog, atomically: true, encoding: .utf8)

        let grokLines = GrokTranscripts.transcript(at: grokLog)
        #expect(
            grokLines.map(\.label) == ["Task", "Tool", "Result", "Reply"],
            "Grok reasoning is dropped while messages and tool work remain")
        #expect(
            grokLines.map(\.text) == [
                "Do the thing", "read_file(target_file: README.md)",
                "file contents", "Done",
            ])
    }

    @Test func usageDoesNotCountCacheReadsTwice() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let grokUsage = try sessionFolder(in: tmp).appendingPathComponent("updates.jsonl")
        try fixture("grok/grok-updates-turn-completed.jsonl").write(to: grokUsage, atomically: true, encoding: .utf8)

        let grokSamples = AgentUsage.samples(at: grokUsage, .grok)
        try #require(grokSamples.count == 1 && grokSamples[0].model == "grok-4.6-build")
        #expect(
            grokSamples[0].tally == TokenTally(input: 60, output: 20, cacheRead: 40, cacheWrite: 5),
            "Grok cache reads are not counted twice")
    }

    // MARK: - Malformed input: Grok writes these files, not Yongkang.

    @Test(arguments: [
        ("grok/grok-transcript-truncated-final-line.jsonl", ["Task", "Result"]),
        ("grok/grok-transcript-non-json-line.jsonl", ["Task", "Reply"]),
        ("grok/grok-transcript-empty.jsonl", []),
        ("grok/grok-transcript-unexpected-type.jsonl", ["Task", "Reply"]),
    ])
    func malformedChatHistoryKeepsEveryReadableLine(path: String, labels: [String]) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("chat_history.jsonl")
        try fixture(path).write(to: log, atomically: true, encoding: .utf8)
        #expect(
            GrokTranscripts.transcript(at: log).map(\.label) == labels,
            "a bad line is skipped on its own, without losing the lines around it")
    }

    @Test func chatHistoryCutMidCharacterKeepsItsCompleteLines() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("chat_history.jsonl")
        try
            (Data(try fixture("grok/grok-transcript-truncated-final-line.jsonl").utf8)
            + Data("\u{2014}".utf8.dropLast(1))).write(to: log)
        #expect(
            GrokTranscripts.transcript(at: log).map(\.label) == ["Task", "Result"],
            "one half-written character costs its own line, not the whole file")
    }

    @Test(arguments: [
        ("grok/grok-updates-truncated-final-line.jsonl", 1),
        ("grok/grok-updates-non-json-line.jsonl", 2),
        ("grok/grok-updates-empty.jsonl", 0),
        ("grok/grok-updates-unexpected-type.jsonl", 1),
    ])
    func malformedUsageKeepsEveryCompleteTurn(path: String, turns: Int) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let usage = tmp.appendingPathComponent("updates.jsonl")
        try fixture(path).write(to: usage, atomically: true, encoding: .utf8)
        #expect(
            AgentUsage.samples(at: usage, .grok).count == turns,
            "only completed turns count, and a bad line costs nothing but itself")
    }

    @Test func halfWrittenUsageLineIsReadOnceFinished() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let usage = tmp.appendingPathComponent("updates.jsonl")
        try fixture("grok/grok-updates-truncated-final-line.jsonl").write(to: usage, atomically: true, encoding: .utf8)
        #expect(AgentUsage.samples(at: usage, .grok).count == 1, "the half-written turn waits for its newline")
        try append(#"tTokens":30,"cachedReadTokens":200,"cacheCreationTokens":0}}}}"# + "\n", to: usage)
        #expect(
            AgentUsage.samples(at: usage, .grok).count == 2,
            "and is read on the next pass once the CLI finishes writing it")
    }
}

private func sessionFolder(in tmp: URL) throws -> URL {
    let folder = GrokTranscripts.sessionFolder(
        sessionID: UUID(), projectDirectory: URL(fileURLWithPath: "/a/b c"),
        grokHome: tmp.appendingPathComponent(".grok"))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Writes to the end of a file the way an agent's transcript grows: open, seek, write.
private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}
