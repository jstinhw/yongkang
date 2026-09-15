import Foundation
import Testing

@testable import YongkangCore

/// Every test reads through its own `CodexTranscripts`, over a temporary home, with the
/// launch cutoff wound back past the fixtures it just wrote.
@Suite struct CodexTranscriptTests {
    @Test func everyDescendantOfTheLeadsThreadIsItsSubagent() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fleet = try makeFleet(in: tmp)

        let codexAgents = await fleet.codex.subagents(
            sessionID: fleet.session, projectDirectory: tmp, taskIDs: ["edit-todo"])
        #expect(
            codexAgents.map(\.description) == ["edit_todo_frontend", "edit_todo_qa"],
            "every descendant of this session's thread is affiliated with the lead")
        #expect(
            codexAgents.allSatisfy { $0.taskID == "edit-todo" },
            "descendants stay linked by the task in their names")
        #expect(codexAgents.first?.agentType == "Hilbert", "no role recorded falls back to the nickname")
        #expect(codexAgents.last?.agentType == "qa-dev", "a recorded descendant role is kept")
        #expect(codexAgents.allSatisfy { $0.running }, "started descendants remain running until complete")
    }

    @Test func sessionWhoseThreadIsNotOnDiskReadsEmpty() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fleet = try makeFleet(in: tmp)
        #expect(
            await fleet.codex.subagents(sessionID: UUID(), projectDirectory: tmp).isEmpty,
            "a session whose thread is not on disk reads as empty, not a crash")
    }

    @Test func leadIsWatchedThroughItsOwnRollout() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fleet = try makeFleet(in: tmp)
        #expect(
            await fleet.codex.transcriptURL(sessionID: fleet.session, projectDirectory: tmp)?.lastPathComponent
                == "rollout-lead.jsonl",
            "a Codex lead is watched through its own rollout, not one it spawned")
        #expect(
            await fleet.codex.transcriptURL(sessionID: UUID(), projectDirectory: tmp) == nil,
            "a thread not on disk yet has no transcript to read, rather than the wrong one")
    }

    @Test func lastMarkerWrittenWins() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fleet = try makeFleet(in: tmp)
        try completeChild(fleet)
        #expect(CodexTranscripts.isRunning(fleet.child) == false, "the last marker written wins")
    }

    // One session's scan must not hide another session's unchanged rollout.
    @Test func concurrentSessionsResolveIndependently() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fleet = try makeFleet(in: tmp)
        let secondSession = UUID()
        let secondRollout = fleet.day.appendingPathComponent("rollout-second.jsonl")
        try [
            #"{"type":"session_meta","payload":{"id":"thread-second","cwd":"\#(tmp.path)","source":"cli"}}"#,
            String(repeating: " ", count: 600_000),
            CodexProvider.marker(secondSession),
        ].joined(separator: "\n").write(to: secondRollout, atomically: true, encoding: .utf8)

        _ = await fleet.codex.transcriptURL(sessionID: UUID(), projectDirectory: tmp)
        #expect(
            await fleet.codex.transcriptURL(sessionID: secondSession, projectDirectory: tmp)?.standardizedFileURL
                == secondRollout.standardizedFileURL,
            "concurrent sessions resolve independently, even beyond the old prompt window")
    }

    @Test func onlineAgentsCountTheLeadAndRunningDescendants() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fleet = try makeFleet(in: tmp)
        let codexAgents = await fleet.codex.subagents(
            sessionID: fleet.session, projectDirectory: tmp, taskIDs: ["edit-todo"])
        var project = Project(directory: tmp)
        project.sessions = [
            CodeSession(
                title: "Lead", icon: "", line: "", agent: .codex,
                subagents: codexAgents),
            CodeSession(title: "Server", icon: "", line: ""),
        ]
        #expect(project.onlineAgentCount == 3, "count the lead and every running descendant, excluding services")
    }

    @Test func transcriptDropsReasoningAndDuplicateEvents() throws {
        let codexLines = try childTranscript()
        #expect(
            codexLines.map(\.label) == ["Task", "Tool", "Result", "Reply"],
            "reasoning and the duplicate event_msg lines are dropped")
        #expect(codexLines.map(\.text) == ["Message Type: NEW_TASK", "exec(ls)", "one file", "Done"])
    }

    // What the header tells the reader: an agent that has replied is theirs to answer,
    // one mid-tool-call is not, and a dead process is neither.
    @Test func headerStateFollowsTheLastLine() throws {
        let codexLines = try childTranscript()
        #expect(AgentState.of(lines: codexLines, exited: false) == .waiting)
        #expect(AgentState.of(lines: codexLines.dropLast(), exited: false) == .working)
        #expect(AgentState.of(lines: [], exited: false) == .starting)
        #expect(AgentState.of(lines: codexLines, exited: true) == .exited)
    }

    // MARK: - Malformed input: Codex writes these files, not Yongkang.

    @Test(arguments: [
        ("codex/codex-transcript-truncated-final-line.jsonl", ["Task", "Tool"]),
        ("codex/codex-transcript-non-json-line.jsonl", ["Task", "Reply"]),
        ("codex/codex-transcript-empty.jsonl", []),
        ("codex/codex-transcript-unexpected-type.jsonl", ["Task", "Reply"]),
    ])
    func malformedTranscriptKeepsEveryReadableLine(path: String, labels: [String]) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("rollout.jsonl")
        try fixture(path).write(to: log, atomically: true, encoding: .utf8)
        #expect(
            CodexTranscripts.transcript(at: log).map(\.label) == labels,
            "a bad line is skipped on its own, without losing the lines around it")
    }

    @Test func transcriptCutMidCharacterKeepsItsCompleteLines() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = tmp.appendingPathComponent("rollout.jsonl")
        try
            (Data(try fixture("codex/codex-transcript-truncated-final-line.jsonl").utf8)
            + Data("\u{2014}".utf8.dropLast(1))).write(to: log)
        #expect(
            CodexTranscripts.transcript(at: log).map(\.label) == ["Task", "Tool"],
            "one half-written character costs its own line, not the whole file")
    }

    /// A lead rollout caught while its first line is still being written is not a lead yet,
    /// and a failed read must not stick: once the line lands, the same file resolves.
    @Test func leadWithHalfWrittenSessionMetaResolvesOnceComplete() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let home = tmp.appendingPathComponent(".codex")
        let day = home.appendingPathComponent("sessions/2026/09/01")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let session = UUID()
        let lead = day.appendingPathComponent("rollout-lead.jsonl")
        let full = try rolloutFixture("codex/codex-rollout-lead.jsonl", cwd: tmp, session: session)
        let codex = CodexTranscripts(codexHome: home, launched: .distantPast)

        try String(full.prefix(40)).write(to: lead, atomically: true, encoding: .utf8)
        #expect(
            await codex.transcriptURL(sessionID: session, projectDirectory: tmp) == nil,
            "a half-written session_meta line reads as no lead, not a crash")
        try full.write(to: lead, atomically: true, encoding: .utf8)
        #expect(
            await codex.transcriptURL(sessionID: session, projectDirectory: tmp)?.lastPathComponent
                == "rollout-lead.jsonl",
            "the completed rollout resolves on the next scan")
    }
}

/// A lead's rollout tree on disk: the lead, an unrelated session in the same project, a
/// child the lead spawned, and a grandchild the child spawned.
private struct CodexFleet {
    let home: URL
    /// Reads this fleet, and only rollouts written since `.distantPast`: every fixture here.
    let codex: CodexTranscripts
    let day: URL
    let session: UUID
    let child: URL
}

// Codex picks its own thread id, so its lead is found by the session id its opening
// prompt quotes, and its subagents by the rollouts pointing back at that thread.
private func makeFleet(in project: URL) throws -> CodexFleet {
    let codexHome = project.appendingPathComponent(".codex")
    let day = codexHome.appendingPathComponent("sessions/2026/09/01")
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let session = UUID()
    func rollout(_ name: String, _ text: String) throws -> URL {
        let url = day.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    _ = try rollout(
        "rollout-lead.jsonl",
        rolloutFixture("codex/codex-rollout-lead.jsonl", cwd: project, session: session))
    _ = try rollout(
        "rollout-other.jsonl",
        #"{"type":"session_meta","payload":{"id":"thread-other","cwd":"\#(project.path)","source":"cli"}}"#)
    let child = try rollout(
        "rollout-child.jsonl",
        rolloutFixture("codex/codex-rollout-child.jsonl", cwd: project, session: session))
    _ = try rollout(
        "rollout-grandchild.jsonl",
        rolloutFixture("codex/codex-rollout-grandchild.jsonl", cwd: project, session: session))
    return CodexFleet(
        home: codexHome, codex: CodexTranscripts(codexHome: codexHome, launched: .distantPast), day: day,
        session: session, child: child)
}

/// A rollout fixture with its `{{CWD}}` and `{{MARKER}}` stand-ins filled in. The opening
/// prompt carries the marker as `AgentCommand.line` actually writes it: the marker is the
/// whole join, so the real one goes in rather than a stand-in.
private func rolloutFixture(_ path: String, cwd: URL, session: UUID) throws -> String {
    try fixture(path)
        .replacingOccurrences(of: "{{CWD}}", with: cwd.path)
        .replacingOccurrences(of: "{{MARKER}}", with: CodexProvider.marker(session))
}

/// The child's turn ends: Codex appends `task_complete` after its `task_started`.
private func completeChild(_ fleet: CodexFleet) throws {
    try
        ((try String(contentsOf: fleet.child, encoding: .utf8))
        + "\n" + #"{"type":"event_msg","payload":{"type":"task_complete"}}"#)
        .write(to: fleet.child, atomically: true, encoding: .utf8)
}

/// The child rollout's transcript after its turn completed. Read straight off the file,
/// so it touches none of the discovery caches.
private func childTranscript() throws -> [TranscriptLine] {
    let tmp = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let child = tmp.appendingPathComponent("rollout-child.jsonl")
    try
        (rolloutFixture("codex/codex-rollout-child.jsonl", cwd: tmp, session: UUID())
        + "\n" + #"{"type":"event_msg","payload":{"type":"task_complete"}}"#)
        .write(to: child, atomically: true, encoding: .utf8)
    return CodexTranscripts.transcript(at: child)
}
