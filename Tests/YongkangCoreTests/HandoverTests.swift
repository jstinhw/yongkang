import Foundation
import Testing

@testable import YongkangCore

/// The review screen's own two claims: that the summary quotes the batch instead of
/// inventing one, and that the commit button either commits or says why it did not.
@Suite struct HandoverTests {

    /// `ChangeSummary` never reads the disk: the project folder is only a URL on its cards.
    private static let directory = URL(fileURLWithPath: "/nonexistent/handover-project")

    private static let tree = ["Sources/Loader.swift", "Tests/Loader.swift", "Sources/Untouched.swift"]
        .map { FileChange(path: $0, added: $0.hasPrefix("Tests") ? 4 : 20, removed: 1, untracked: false) }

    private static func card(
        _ id: String, _ title: String, _ status: String,
        kind: EntryKind = .task, project: String? = "launch"
    ) -> NotebookCard {
        NotebookCard(
            id: id, url: directory, kind: kind, title: title, status: status,
            project: project, dependsOn: [])
    }

    /// An Engineering Lead on two tasks: `read-blockers` built and passed QA, `wire-auth`
    /// still has an endpoint running.
    private static func leadProject(wireAuth: String = "active") -> (project: Project, lead: CodeSession) {
        var lead = CodeSession(
            title: "Engineering Lead", icon: "", line: "", agent: .claude,
            taskIDs: ["wire-auth", "read-blockers"])
        lead.coordination = LeadCoordination(
            strategy: "Two builds in parallel, QA after each.",
            contextSummary: "",
            workers: [
                LeadWork(
                    id: "a", taskID: "read-blockers", title: "Reader",
                    skill: "backend-dev",
                    paths: ["Sources/Loader.swift", "Sources/Gone.swift"], state: "done",
                    checkpoint: "Reader owns the loader; the UI never parses.",
                    report: "Reader landed."),
                LeadWork(
                    id: "b", taskID: "read-blockers", title: "Check it",
                    skill: "qa-dev", paths: ["Sources/Loader.swift", "Tests/Loader.swift"],
                    state: "done", report: "Passed."),
                LeadWork(
                    id: "c", taskID: "wire-auth", title: "Endpoint",
                    skill: "backend-dev", state: "running"),
            ])
        var project = Project(directory: directory, entries: [])
        project.cards = [
            card("wire-auth", "Wire auth", wireAuth),
            card("read-blockers", "Read blockers", "done"),
            card("launch", "Launch", "done", kind: .project, project: nil),
        ]
        project.sessions = [lead]
        return (project, lead)
    }

    @Test func noBatchNothingToSummarise() {
        #expect(
            ChangeSummary.of(Project(directory: Self.directory, entries: [])).isEmpty,
            "no batch, nothing to summarise")
    }

    @Test func summaryQuotesTheBatch() throws {
        let summary = ChangeSummary.of(Self.leadProject().project, changes: Self.tree)
        try #require(
            summary.tasks.map(\.id) == ["read-blockers", "wire-auth"],
            "finished work reads first, and a project card is not a task")
        #expect(summary.finished.map(\.id) == ["read-blockers"])
        #expect(summary.tasks[0].builds.map(\.id) == ["a"], "QA is separated from the build it accepted")
        #expect(summary.tasks[0].reviews.map(\.id) == ["b"], "QA is separated from the build it accepted")
        #expect(
            summary.decisions == [
                "Two builds in parallel, QA after each.",
                "Reader owns the loader; the UI never parses.",
            ])
        #expect(
            summary.commitMessage == "Read blockers",
            "the subject names what passed QA, never work still running")
        #expect(
            summary.tasks[0].files.map(\.path) == ["Sources/Loader.swift", "Tests/Loader.swift"],
            "a file two workers on one task both claim is listed once, and a path that is not in the working tree is not invented into a row"
        )
        #expect(summary.tasks[0].added == 24, "a task counts its own files, not the whole tree")
        #expect(summary.tasks[0].removed == 2, "a task counts its own files, not the whole tree")
        #expect(summary.tasks[1].files.isEmpty, "work that reported no paths claims nothing")
        #expect(
            summary.unclaimed.map(\.path) == ["Sources/Untouched.swift"],
            "a changed file no task claimed is shown, not folded into one")
        #expect(summary.peak == 21, "bars share one scale across every task")
    }

    @Test func noWorkingTreeClaimsNothing() {
        #expect(
            ChangeSummary.of(Self.leadProject().project).unclaimed.isEmpty,
            "with no working tree to join, no file is claimed or orphaned")
    }

    @Test func commitMessageWithNothingInFlight() {
        #expect(
            ChangeSummary.of(Self.leadProject(wireAuth: "done").project).commitMessage
                == "Finish 2 tasks: Wire auth, Read blockers",
            "with nothing in flight the notebook's own order stands")
    }

    @Test func onlyFinishedUncommittedWorkWaits() throws {
        let summary = ChangeSummary.of(Self.leadProject().project, changes: Self.tree)
        #expect(
            summary.waiting.map(\.id) == ["read-blockers"],
            "only a finished task with uncommitted work waits on the user")
        let first = try #require(summary.tasks.first)
        #expect(
            first.commitPaths == ["Sources/Loader.swift", "Tests/Loader.swift"],
            "approving a task commits its own files, never the whole tree")
        #expect(summary.sharing("Sources/Loader.swift", besides: first) == nil)
    }

    @Test func recordsOnDiskKeepWorkWaiting() throws {
        let (project, lead) = Self.leadProject()
        var relaunched = project
        relaunched.sessions = []
        relaunched.records = [lead.id: try #require(lead.coordination)]
        #expect(
            ChangeSummary.of(relaunched, changes: Self.tree).waiting.map(\.id) == ["read-blockers"],
            "records on disk keep work waiting for review after its lead session is gone")
    }

    @Test func resultIsItsOwnSection() {
        #expect(
            LeadCoordination.section(
                "Result",
                of: "---\nkind: run\n---\n# W\n\n## Done when\n\n- a\n\n"
                    + "## Result\n\nVerdict **pass**.\n\n`tsc` exit 0\n\n## Later\n\nx")
                == "Verdict **pass**.\n\n`tsc` exit 0",
            "a work record's Result is its own section and stops at the next heading")
    }

    // The commit itself, against a real repo: this is the app's only write to one.

    @Test func commitRefusesAFolderThatIsNotARepository() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(
            GitChanges.commit(message: "nothing here", in: dir.appendingPathComponent("repo")) != nil,
            "a folder that is not a repository is refused, not silently skipped")
    }

    @Test func commitAgainstARealRepository() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = dir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        for arguments in [
            ["init", "--quiet"], ["config", "user.email", "selftest@example.com"],
            ["config", "user.name", "Selftest"],
        ] {
            try git(arguments, in: repo)
        }
        try "one\n".write(to: repo.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        #expect(GitChanges.commit(message: "   ", in: repo) != nil, "a blank message is refused")
        #expect(GitChanges.changes(in: repo).map(\.path) == ["new.txt"])
        #expect(GitChanges.commit(message: "Add one file", in: repo) == nil)
        #expect(GitChanges.changes(in: repo).isEmpty, "an untracked file is staged and committed")
        #expect(GitChanges.head(in: repo)?.hasSuffix("Add one file") == true)
        #expect(
            GitChanges.commit(message: "Again", in: repo) != nil,
            "an empty commit reports git's own refusal rather than claiming success")
        for name in ["mine.txt", "theirs.txt"] {
            try "x\n".write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        #expect(
            GitChanges.commit(message: "Nothing", paths: [], in: repo) != nil,
            "a task with no files left is refused rather than committing everything")
        #expect(GitChanges.commit(message: "Approve mine", paths: ["mine.txt"], in: repo) == nil)
        #expect(
            GitChanges.changes(in: repo).map(\.path) == ["theirs.txt"],
            "approving one task leaves every other task's files uncommitted")
    }

    @Test func initializeMakesARepository() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fresh = dir.appendingPathComponent("fresh")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try "x\n".write(to: fresh.appendingPathComponent("task.txt"), atomically: true, encoding: .utf8)
        let becomes: Comment = "a folder the agents work in becomes a repository"
        try #require(!GitChanges.isRepository(fresh), becomes)
        #expect(GitChanges.initialize(in: fresh) == nil, becomes)
        #expect(GitChanges.isRepository(fresh), becomes)
        let waiting: Comment = "created, not committed: everything is still waiting for review"
        #expect(GitChanges.changes(in: fresh).map(\.path) == ["task.txt"], waiting)
        #expect(GitChanges.head(in: fresh) == nil, waiting)
        #expect(GitChanges.branch(in: fresh) != nil, "a repository with no commit still names its branch")
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        git.arguments = ["git"] + arguments
        git.currentDirectoryURL = directory
        git.standardOutput = FileHandle.nullDevice
        git.standardError = FileHandle.nullDevice
        try git.run()
        git.waitUntilExit()
        try #require(git.terminationStatus == 0, "git \(arguments.joined(separator: " ")) failed")
    }
}
