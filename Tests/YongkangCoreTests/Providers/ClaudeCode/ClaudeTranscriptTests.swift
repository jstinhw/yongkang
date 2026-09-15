import Foundation
import Testing

@testable import YongkangCore

/// No process-global state: every read goes through an explicit `claudeHome` under a fresh
/// temporary directory, so these run in parallel.
@Suite struct ClaudeTranscriptTests {
    private let sid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    // Subagent transcripts live under a project's slugged folder — the slug, the pure
    // finished-detection, and an end-to-end read against fixture files.
    @Test func sessionFolderSlugsTheProjectPath() {
        #expect(
            ClaudeTranscripts.sessionFolder(
                sessionID: sid, projectDirectory: URL(fileURLWithPath: "/a/b c"),
                claudeHome: URL(fileURLWithPath: "/home/.claude")
            ).path
                == "/home/.claude/projects/-a-b c/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }

    @Test(arguments: [
        ("{\"tool_use_id\":\"toolu_1\"}", true, "a tool_result for the call finishes a foreground agent"),
        ("{\"tool_use_id\": \"toolu_1\"}", true, "a tool_result finishes it whether or not the JSON is spaced"),
        ("{\"id\":\"toolu_1\"}", false, "a tool_use block must not read as its own result"),
    ])
    func foregroundAgentFinishesOnItsResult(transcript: String, finished: Bool, why: String) {
        #expect(
            ClaudeTranscripts.isFinished(
                agentID: "agent1", label: "task-frontend",
                toolUseID: "toolu_1", in: transcript) == finished,
            "\(why)")
    }

    /// A background agent's life in the lead's transcript: launched, stopped, then resumed.
    @Test func backgroundAgentFinishesOnItsNotificationUntilMessaged() throws {
        let lines = try fixture("claude/claude-background-agent.jsonl").components(separatedBy: "\n")
        try #require(lines.count == 3)
        func finished(after count: Int) -> Bool {
            ClaudeTranscripts.isFinished(
                agentID: "agent1", label: "task-frontend", toolUseID: "toolu_async",
                in: lines.prefix(count).joined(separator: "\n"))
        }
        #expect(!finished(after: 1), "an async launch receipt means the agent is still running")
        #expect(finished(after: 2), "the matching task notification ends a background agent")
        #expect(!finished(after: 3), "messaging a stopped agent resumes it")
    }

    @Test func subagentsReadFromTheSessionFolder() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let session = try makeSession(in: tmp)

        let subagents = ClaudeTranscripts.subagents(
            sessionID: session.id, projectDirectory: tmp,
            claudeHome: session.home)
        #expect(subagents.map(\.description) == ["Find Y", "Research X"], "sorted by description")
        #expect(
            subagents.first { $0.id == "done1" }?.running == false,
            "a result in the parent transcript means done")
        #expect(subagents.first { $0.id == "running1" }?.running == true, "no result yet means still running")
        #expect(subagents.first { $0.id == "done1" }?.agentType == "claude-code-guide")
        #expect(
            subagents.first { $0.id == "done1" }?.transcriptURL
                == session.subagentsDir.appendingPathComponent("agent-done1.jsonl"))
    }

    @Test func sessionWithoutSubagentsFolderReadsEmpty() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let session = try makeSession(in: tmp)
        #expect(
            ClaudeTranscripts.subagents(
                sessionID: UUID(), projectDirectory: tmp,
                claudeHome: session.home
            ).isEmpty,
            "a session with no subagents folder reads as empty, not a crash")
    }

    @Test func leadIsWatchedThroughTheFileBesideItsFolder() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let session = try makeSession(in: tmp)
        #expect(
            session.leadLog.path == session.folder.path + ".jsonl" && !session.leadLog.hasDirectoryPath,
            "a lead is watched through the file beside its subagents' folder, not a folder")
    }

    // The viewer's own read: a task, a tool call (thinking dropped along the way), its
    // result, and a reply, out of the same shape a subagent's own transcript is in.
    @Test func viewerReadDropsThinking() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let subagentLog = tmp.appendingPathComponent("agent-done1.jsonl")
        try fixture("claude/claude-subagent-transcript.jsonl").write(to: subagentLog, atomically: true, encoding: .utf8)

        let parsed = ClaudeTranscripts.transcript(at: subagentLog)
        #expect(parsed.map(\.label) == ["Task", "Tool", "Result", "Reply"], "thinking blocks are dropped")
        #expect(
            parsed.map(\.text) == [
                "Do the thing", "WebSearch(query: claude code)",
                "some results here", "Here is the answer",
            ])
        #expect(
            ClaudeTranscripts.transcript(at: tmp.appendingPathComponent("missing.jsonl")).isEmpty,
            "a transcript that is not there yet reads as empty, not a crash")
    }

    @Test func subagentCarriesTheTaskItsDescriptionNames() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let session = try makeSession(in: tmp)
        #expect(
            ClaudeTranscripts.subagents(
                sessionID: session.id, projectDirectory: tmp,
                taskIDs: ["research-x"], claudeHome: session.home
            )
            .first { $0.id == "done1" }?.taskID == "research-x",
            "a Claude subagent carries the task its description names")
    }

    @Test func nestedAgentsFinishInTheirSpawningAgentsTranscript() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let session = try makeSession(in: tmp)
        try #"{"agentType":"qa-dev","description":"Nested QA","toolUseId":"nested-call"}"#
            .write(
                to: session.subagentsDir.appendingPathComponent("agent-nested.meta.json"),
                atomically: true, encoding: .utf8)
        try fixture("claude/claude-nested-agent-transcript.jsonl")
            .write(
                to: session.subagentsDir.appendingPathComponent("agent-done1.jsonl"),
                atomically: true, encoding: .utf8)
        #expect(
            ClaudeTranscripts.subagents(
                sessionID: session.id, projectDirectory: tmp,
                claudeHome: session.home
            ).first { $0.id == "nested" }?.running == false,
            "nested Claude agents finish in their spawning agent's transcript")
    }

    // MARK: - Malformed input: Claude Code writes these files, not Yongkang.

    @Test(arguments: [
        ("claude/claude-transcript-truncated-final-line.jsonl", ["Task", "Tool"]),
        ("claude/claude-transcript-non-json-line.jsonl", ["Task", "Reply"]),
        ("claude/claude-transcript-empty.jsonl", []),
        ("claude/claude-transcript-unexpected-type.jsonl", ["Task", "Reply"]),
    ])
    func malformedTranscriptKeepsEveryReadableLine(path: String, labels: [String]) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("agent.jsonl")
        try fixture(path).write(to: log, atomically: true, encoding: .utf8)
        #expect(
            ClaudeTranscripts.transcript(at: log).map(\.label) == labels,
            "a bad line is skipped on its own, without losing the lines around it")
    }

    @Test func transcriptCutMidCharacterKeepsItsCompleteLines() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("agent.jsonl")
        try cutMidCharacter("claude/claude-transcript-truncated-final-line.jsonl").write(to: log)
        #expect(
            ClaudeTranscripts.transcript(at: log).map(\.label) == ["Task", "Tool"],
            "one half-written character costs its own line, not the whole file")
    }

    @Test func leadTranscriptCutMidCharacterStillFinishesItsSubagents() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let session = try makeSession(in: tmp)
        var lead = try Data(contentsOf: session.leadLog)
        lead.append(contentsOf: Array("\n{\"type\":\"assistant\",\"text\":\"\u{2014}".utf8.dropLast(1)))
        try lead.write(to: session.leadLog)
        #expect(
            ClaudeTranscripts.subagents(
                sessionID: session.id, projectDirectory: tmp,
                claudeHome: session.home
            )
            .first { $0.id == "done1" }?.running == false,
            "a lead caught mid-character still has the result that finished its subagent")
    }
}

/// One lead session on disk, as Claude Code lays it out.
private struct ClaudeSession {
    let id: UUID
    let home: URL
    let folder: URL
    let subagentsDir: URL
    let leadLog: URL
}

/// A lead in `project` with two subagents: `done1`, whose result is already in the lead's
/// transcript, and `running1`, whose result is not.
private func makeSession(in project: URL) throws -> ClaudeSession {
    let claudeHome = project.appendingPathComponent(".claude")
    let sessionID = UUID()
    let sessionFolder = ClaudeTranscripts.sessionFolder(
        sessionID: sessionID, projectDirectory: project,
        claudeHome: claudeHome)
    let subagentsDir = sessionFolder.appendingPathComponent("subagents")
    try FileManager.default.createDirectory(at: subagentsDir, withIntermediateDirectories: true)
    try #"{"agentType":"claude-code-guide","description":"Research X","toolUseId":"toolu_done"}"#
        .write(to: subagentsDir.appendingPathComponent("agent-done1.meta.json"), atomically: true, encoding: .utf8)
    try #"{"agentType":"Explore","description":"Find Y","toolUseId":"toolu_running"}"#
        .write(to: subagentsDir.appendingPathComponent("agent-running1.meta.json"), atomically: true, encoding: .utf8)
    let leadLog = ClaudeTranscripts.transcriptURL(
        sessionID: sessionID, projectDirectory: project,
        claudeHome: claudeHome)
    try #"{"type":"tool_result","tool_use_id":"toolu_done"}"#
        .write(to: leadLog, atomically: true, encoding: .utf8)
    return ClaudeSession(
        id: sessionID, home: claudeHome, folder: sessionFolder,
        subagentsDir: subagentsDir, leadLog: leadLog)
}

/// A fixture whose last write stopped two bytes into a three-byte character (an em dash).
private func cutMidCharacter(_ path: String) throws -> Data {
    Data(try fixture(path).utf8) + Data("\u{2014}".utf8.dropLast(1))
}
