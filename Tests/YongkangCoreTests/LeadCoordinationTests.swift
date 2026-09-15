import Foundation
import Testing

@testable import YongkangCore

/// A lead's durable plan and each runtime observation must stay correctly scoped.
///
/// Loading a plan measures workers through the shared Claude Code provider's usage cursors.
/// Every test writes its transcript under its own temporary folder, so no cursor an earlier
/// test left can match.
@Suite struct LeadCoordinationTests {

    /// The session every record in `Fixtures/coordination/` is filed under.
    private static let id = UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!
    private static var prefix: String { id.uuidString.lowercased() }
    private static let noon = AgentUsage.date("2026-09-07T12:00:00Z")!

    private struct Seeded {
        let root: URL
        let transcript: URL
        let worker: SubagentStatus
        let session: CodeSession
    }

    /// `runs/` as a lead leaves it: its plan, two workers on `auth`, and the records that
    /// must be refused — another session's, a mismatched task, unsafe IDs, and one
    /// symlinked to a file outside the folder.
    private func seed(in dir: URL) throws -> Seeded {
        let fm = FileManager.default
        let root = dir.appendingPathComponent("coordination")
        let runs = root.appendingPathComponent("runs")
        try fm.createDirectory(at: runs, withIntermediateDirectories: true)
        for record in [
            "coordination", "work-auth-api", "work-auth-qa", "work-other-session", "work-unsafe",
            "work-wrong-task", "work-bad-dependency", "work-outside",
        ] {
            try file(record, into: runs)
        }
        let outside = dir.appendingPathComponent("outside-coordination.md")
        let linked = runs.appendingPathComponent(Self.prefix + "-work-outside.md")
        try fm.moveItem(at: linked, to: outside)
        try fm.createSymbolicLink(at: linked, withDestinationURL: outside)

        let transcript = root.appendingPathComponent("worker.jsonl")
        try fixture("coordination/worker.jsonl").write(to: transcript, atomically: true, encoding: .utf8)
        let worker = SubagentStatus(
            id: "runtime-1", description: "auth-api", agentType: "backend-dev",
            running: false, transcriptURL: transcript, taskID: "auth")
        let session = CodeSession(
            id: Self.id, title: "Engineering Lead", icon: "", line: "", agent: .claude,
            taskIDs: ["auth"], subagents: [worker])
        return Seeded(root: root, transcript: transcript, worker: worker, session: session)
    }

    /// Copies `Fixtures/coordination/<record>.md` into `runs/` under the session's prefix.
    private func file(_ record: String, into runs: URL) throws {
        try fixture("coordination/\(record).md")
            .write(
                to: runs.appendingPathComponent(Self.prefix + "-" + record + ".md"),
                atomically: true, encoding: .utf8)
    }

    @Test func noRecordsNoPlan() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = CodeSession(
            id: Self.id, title: "Engineering Lead", icon: "", line: "", agent: .claude,
            taskIDs: ["auth"])
        #expect(await LeadCoordination.load(root: dir.appendingPathComponent("coordination"), session: session) == nil)
    }

    @Test func planReadsTheCoordinationRecord() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seeded = try seed(in: dir)

        let plan = try #require(await LeadCoordination.load(root: seeded.root, session: seeded.session))
        #expect(plan.parallelLimit == 2)
        #expect(plan.estimatedTokens == 12000)
        #expect(plan.estimatedMinutes == 8.5)
        #expect(plan.contextSummary == "Resume from the handoff.")
        #expect(plan.updatedAt != nil)
        #expect(
            plan.workers.map(\.id) == ["auth-api", "auth-qa"],
            "cross-session, mismatched task, unsafe IDs and external symlinks are rejected")
    }

    @Test func returnedWorkerIsMeasuredAndScoped() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seeded = try seed(in: dir)

        let plan = try #require(await LeadCoordination.load(root: seeded.root, session: seeded.session))
        try #require(plan.workers.count == 2)
        let api = plan.workers[0]
        #expect(api.actualTokens == 90)
        #expect(api.measuredTokens == 120)
        #expect(api.usedTokens == 120)
        #expect(api.tokenSource == "Measured")
        #expect(api.measuredModel == "observed-model")
        let returned: Comment = "a returned worker still needs QA; runtime completion cannot mark work done"
        #expect(api.state == "review", returned)
        #expect(api.runtimeRunning == false, returned)
        #expect(api.elapsedMinutes(now: Self.noon.addingTimeInterval(600)) == 2)
        #expect(
            api.paths == ["Sources/API.swift", "Sources/Routes.swift"],
            "reported paths are repo-relative or dropped; ./ is normalised away")
        #expect(plan.workers[1].paths.isEmpty, "a record with no paths claims no files")
        #expect(api.dependsOn == ["auth-contract"])
        #expect(api.contextWindow == 2000)
        #expect(api.contextTokens == 500)
        #expect(api.report == "API ready for QA.")
    }

    @Test func queuedWorkerHasNoMetrics() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seeded = try seed(in: dir)

        let plan = try #require(await LeadCoordination.load(root: seeded.root, session: seeded.session))
        let qa = try #require(plan.workers.last)
        let unavailable: Comment = "missing or invalid metrics stay unavailable instead of becoming zero"
        #expect(qa.usedTokens == nil, unavailable)
        #expect(qa.estimatedTokens == nil, unavailable)
        #expect(qa.estimatedMinutes == nil, unavailable)
        #expect(qa.contextTokens == nil, unavailable)
        #expect(qa.contextWindow == nil, unavailable)
        #expect(qa.elapsedMinutes() == nil, unavailable)
        let queued: Comment = "a queued reuse cannot claim previous usage or show the contract as a result"
        #expect(qa.report.isEmpty, queued)
        #expect(qa.runtimeRunning == nil, queued)
    }

    @Test func nextPollIsStable() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seeded = try seed(in: dir)

        let plan = try #require(await LeadCoordination.load(root: seeded.root, session: seeded.session))
        #expect(
            await LeadCoordination.load(root: seeded.root, session: seeded.session) == plan,
            "the next poll neither double-counts usage nor changes finished work")
    }

    @Test func allReadsRecordsWithNoSession() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seeded = try seed(in: dir)

        let plan = try #require(await LeadCoordination.load(root: seeded.root, session: seeded.session))
        let disk = LeadCoordination.all(root: seeded.root)
        let fromDisk: Comment = "records are read from disk with no live session; a mislabelled one is still refused"
        #expect(Array(disk.keys) == [Self.id], fromDisk)
        #expect(disk[Self.id]?.strategy == plan.strategy, fromDisk)
        let unobserved: Comment = "without a session there is no runtime to observe and no batch to filter by"
        #expect(disk[Self.id]?.workers.first { $0.id == "auth-api" }?.measuredTokens == nil, unobserved)
        #expect(disk[Self.id]?.workers.contains { $0.id == "wrong-task" } == true, unobserved)
    }

    @Test func workFindsItsOwnSubagent() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seeded = try seed(in: dir)

        #expect(LeadWork(id: "auth-api").subagent(in: seeded.session)?.id == seeded.worker.id)
        #expect(
            LeadWork(id: "auth").subagent(in: seeded.session) == nil,
            "a task substring must not claim a sibling worker's transcript")
        #expect(
            LeadWork(id: "auth-api", agentID: "missing").subagent(in: seeded.session) == nil,
            "a recorded agent ID wins over a similar label")
    }

    @Test func elapsedMinutesComeFromTimestamps() {
        let noon = Self.noon
        #expect(
            LeadWork(id: "running", state: "running", startedAt: noon)
                .elapsedMinutes(now: noon.addingTimeInterval(180)) == 3)
        #expect(
            LeadWork(id: "returned", state: "running", startedAt: noon, runtimeRunning: false)
                .elapsedMinutes(now: noon.addingTimeInterval(180)) == nil,
            "a returned agent without a finish timestamp has unknown elapsed time")
    }

    @Test func retriedAttemptsCountABoundarySampleOnce() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seeded = try seed(in: dir)

        // A first poll, so the transcript is read incrementally across the retry.
        _ = await LeadCoordination.load(root: seeded.root, session: seeded.session)
        try file("work-auth-z-retry", into: seeded.root.appendingPathComponent("runs"))
        try append(fixture("coordination/worker-retry.jsonl"), to: seeded.transcript)
        let retried = try #require(await LeadCoordination.load(root: seeded.root, session: seeded.session))
        let boundary: Comment =
            "reused threads measure (start, finish] so adjacent attempts count a boundary sample once"
        #expect(retried.workers.first?.measuredTokens == 150, boundary)
        #expect(retried.workers.last?.measuredTokens == 60, boundary)
    }

    // MARK: - Malformed records (trust boundary)
    //
    // Run records are written by agents. Anything that could name a file or a worker outside
    // this project, or smuggle one ID in as another, is refused rather than read.

    @Test(arguments: [
        ("work_id: auth/api\ntask: auth", "auth-api", "an ID with a slash"),
        ("work_id: ../probe\ntask: auth", "probe", "an ID that walks up"),
        ("work_id: /etc/probe\ntask: auth", "probe", "an absolute ID"),
        ("work_id: \"auth\\napi\"\ntask: auth", "auth-api", "an escaped newline in a quoted ID"),
        ("work_id: auth\n-api\ntask: auth", "auth-api", "a newline splits an ID rather than joining the file's name"),
        ("work_id: probe\ntask: ../auth", "probe", "a task that walks up"),
        ("work_id: probe\ntask: auth/../other", "probe", "a task with a slash"),
        ("work_id: probe\ntask: auth\ndepends_on: [/etc/passwd]", "probe", "an absolute dependency"),
        ("work_id: probe\ntask: auth\nstatus: shipped", "probe", "a status the lifecycle does not have"),
        ("work_id:\ntask: auth", "probe", "an empty ID"),
        ("work_id: probe\ntask", "probe", "a record cut off before its task"),
    ])
    func refusesAnUnsafeRecord(fields: String, suffix: String, why: String) throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runs = dir.appendingPathComponent("runs")
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        try "---\nkind: run\nsession: \(Self.id.uuidString)\n\(fields)\n---\nDurable details."
            .write(
                to: runs.appendingPathComponent("\(Self.prefix)-work-\(suffix).md"),
                atomically: true, encoding: .utf8)

        #expect((LeadCoordination.all(root: dir)[Self.id]?.workers ?? []).isEmpty, Comment(rawValue: why))
    }

    @Test func pathsThatLeaveTheProjectAreDropped() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runs = dir.appendingPathComponent("runs")
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        try """
        ---
        kind: run
        session: \(Self.id.uuidString)
        work_id: probe
        task: auth
        paths: [ok.swift, ../up.swift, ./../up.swift, Sources/../../etc/passwd, a/.., /etc/passwd, ~/x, "~root/x", ./, ok/nested.swift]
        ---
        """.write(to: runs.appendingPathComponent("\(Self.prefix)-work-probe.md"), atomically: true, encoding: .utf8)

        let work = try #require(LeadCoordination.all(root: dir)[Self.id]?.workers.first)
        #expect(
            work.paths == ["ok.swift", "ok/nested.swift"],
            "only repo-relative paths that stay inside the project are claimed")
    }

    @Test func runsFolderLinkedOutsideIsNotRead() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let elsewhere = dir.appendingPathComponent("elsewhere")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try file("coordination", into: elsewhere)
        try file("work-auth-qa", into: elsewhere)
        let root = dir.appendingPathComponent("coordination")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("runs"), withDestinationURL: elsewhere)
        let session = CodeSession(
            id: Self.id, title: "Engineering Lead", icon: "", line: "", agent: .claude,
            taskIDs: ["auth"])

        #expect(LeadCoordination.all(root: root).isEmpty, "a runs folder that points elsewhere is not this project's")
        #expect(await LeadCoordination.load(root: root, session: session) == nil)
    }

    @Test func recordThatIsNotTextIsSkipped() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runs = dir.appendingPathComponent("runs")
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        try file("work-auth-qa", into: runs)
        try Data([0x2D, 0x2D, 0x2D, 0x0A, 0xFF, 0xFE, 0x00, 0xC3])
            .write(to: runs.appendingPathComponent("\(Self.prefix)-work-binary.md"))

        #expect(
            LeadCoordination.all(root: dir)[Self.id]?.workers.map(\.id) == ["auth-qa"],
            "an unreadable record is skipped without taking the rest of the folder with it")
    }

    /// Writes to the end of a file the way an agent's transcript grows: open, seek, write.
    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
