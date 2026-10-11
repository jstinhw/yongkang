import Foundation
import Observation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The models are the window's one mutation boundary. What these lock in is what a screen
/// sees of it: a poll that finds nothing new, or news in another project, invalidates nothing.
@Suite @MainActor struct ProjectModelTests {
    /// A folder named `name` under `tmp` with a notebook holding one task.
    private func notebook(_ name: String, in tmp: URL) throws -> URL {
        let directory = tmp.appendingPathComponent(name)
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: NotebookFormat.root(in: directory), project: nil)
        return directory
    }

    /// Whether `change` writes anything `read` reads. Observation calls back synchronously on
    /// the first such write, so there is nothing to wait for beyond the read itself.
    private func invalidates(
        _ read: @autoclosure () -> Any, by change: () async throws -> Void
    ) async rethrows
        -> Bool
    {
        // @unchecked: Observation calls the willSet handler synchronously, on whichever
        // actor wrote — here always the main one, since everything under test is
        // `@MainActor`. Nothing else ever touches the flag.
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        _ = withObservationTracking(read) { flag.fired = true }
        try await change()
        return flag.fired
    }

    @Test func reloadingAnUnchangedNotebookKeepsItsSnapshot() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = ProjectModel(directory: try notebook("app", in: tmp))
        await project.reloadNotebook(frontmatter: true, records: true)
        #expect(project.snapshot.cards.contains { $0.id == "wire-auth" })

        let untouched = await invalidates(project.snapshot) {
            await project.reloadNotebook(frontmatter: true, records: true)
        }
        #expect(!untouched, "a notebook nobody wrote to leaves the snapshot in place")

        let written = try await invalidates(project.snapshot) {
            _ = try NotebookFormat.create(.task, title: "Ship it", in: project.notebookRoot, project: nil)
            await project.reloadNotebook(frontmatter: true, records: true)
        }
        #expect(written, "and a new page replaces it, so the check above can fail")
    }

    @Test func aPollThatChangesOneProjectLeavesTheOtherAlone() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = AppModel()
        let first = app.open(try notebook("first", in: tmp))
        let second = app.open(try notebook("second", in: tmp))
        // The fleet screen, where the poll reads every project in full.
        await app.reloadNow()
        // Its git reads run on after it returns, and a new folder's first one — `git init`,
        // then the untracked notebook — always writes. Landing late, inside the poll below,
        // it read as that poll writing to the first project whenever the full suite was busy.
        try #require(try await eventually { !first.repo.changes.isEmpty })

        var secondChanged = false
        let firstChanged = try await invalidates(
            (first.snapshot, first.sessions, first.repo, first.reviewDrafts, first.summary)
        ) {
            secondChanged = try await invalidates(second.snapshot) {
                _ = try NotebookFormat.create(.task, title: "Ship it", in: second.notebookRoot, project: nil)
                await app.reloadNow()
            }
        }
        #expect(secondChanged, "the poll picked up the new task")
        #expect(!firstChanged, "and nothing a screen of the other project reads was written")
    }

    /// The poll, a forced refresh and the read after a commit overlap, and git answers them in
    /// whatever order it finishes.
    @Test func aRepoReadThatAnswersLateNeverReplacesANewerOne() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = ProjectModel(directory: try notebook("app", in: tmp))
        let older = RepoStatus(changes: [FileChange(path: "old.txt", added: 1, removed: 0, untracked: true)])
        let newer = RepoStatus(changes: [FileChange(path: "new.txt", added: 1, removed: 0, untracked: true)])

        let (reads, read) = AsyncStream.makeStream(of: CheckedContinuation<RepoStatus, Never>.self)
        let slow = Task { await project.refreshRepo { await withCheckedContinuation { read.yield($0) } } }
        var started = reads.makeAsyncIterator()
        let late = try #require(await started.next())

        await project.refreshRepo { newer }
        #expect(project.repo == newer, "a read that started later still shows while the earlier one runs")
        late.resume(returning: older)
        await slow.value
        #expect(project.repo == newer, "and the earlier one, answering last, is dropped")
    }

    /// A cancelled read's git is terminated, and what it returns is an empty tree.
    @Test func aCancelledRepoReadIsNotShown() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = ProjectModel(directory: try notebook("app", in: tmp))
        let shown = RepoStatus(changes: [FileChange(path: "a.txt", added: 1, removed: 0, untracked: true)])
        await project.refreshRepo { shown }

        let (reads, read) = AsyncStream.makeStream(of: CheckedContinuation<RepoStatus, Never>.self)
        let cancelled = Task { await project.refreshRepo { await withCheckedContinuation { read.yield($0) } } }
        var started = reads.makeAsyncIterator()
        let terminated = try #require(await started.next())
        cancelled.cancel()
        terminated.resume(returning: RepoStatus())
        await cancelled.value
        #expect(project.repo == shown)
    }

    /// A folder with `tasks` task pages, each with a body, and one project card.
    private func bigNotebook(tasks: Int, in tmp: URL) throws -> URL {
        let directory = tmp.appendingPathComponent("big")
        let root = NotebookFormat.root(in: directory)
        _ = try NotebookFormat.create(.project, title: "Console", in: root, project: nil)
        for index in 0..<tasks {
            let file = try NotebookFormat.create(.task, title: "Task \(index)", in: root, project: "console")
            let page = try String(contentsOf: file, encoding: .utf8)
            try (page + "\nWhat this task is for.\n\n## Done when\n\n- [ ] It works\n")
                .write(to: file, atomically: true, encoding: .utf8)
        }
        return directory
    }

    /// The main-thread claim, checked rather than asserted from the code's shape: a read of a
    /// notebook with hundreds of pages runs to completion while this test, which is a main-actor
    /// job, never once gives the main actor up. Anything reading there could not have finished.
    @Test func aReloadDoesItsReadingOffTheMainActor() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let directory = try bigNotebook(tasks: 400, in: tmp)

        // What the read costs with nothing competing for the main actor.
        let warm = ProjectModel(directory: directory)
        let started = Date()
        await warm.reloadNotebook(frontmatter: true, records: true)
        let cost = Date().timeIntervalSince(started)
        try #require(warm.snapshot.cards.count == 401, "400 tasks and the project they are filed under")

        // The same read again, from a cold snapshot, started off the main actor.
        // @unchecked: the semaphore is the handoff. The task writes `cards` before it
        // signals and this test reads it only once the signal has arrived.
        final class Answer: @unchecked Sendable { var cards = -1 }
        let answer = Answer()
        let done = DispatchSemaphore(value: 0)
        let reader = ProjectReader(directory: directory)
        Task.detached {
            let read = await reader.notebook(after: NotebookSnapshot(), frontmatter: true, records: true)
            answer.cards = read?.cards.count ?? -1
            done.signal()
        }

        // Hold the main actor without suspending, for long enough that a read running here
        // would have had to finish in this window — and it has no window, because this loop
        // never yields.
        let held = max(cost * 6, 1)
        let start = Date()
        while Date().timeIntervalSince(start) < held {}
        let reading = Int(cost * 1000)
        // `wait` is unavailable in an async context because blocking the cooperative pool
        // can deadlock it. A zero timeout blocks nothing — it asks whether the read has
        // already finished, which is the whole claim — so the ask sits in a synchronous
        // function where the compiler can see that it never waits.
        func finished() -> Bool { done.wait(timeout: .now()) == .success }
        #expect(
            finished() && answer.cards == 401,
            """
            the notebook was read while the main actor was busy for \(Int(held * 1000))ms, \
            so none of it ran there (the read alone costs \(reading)ms)
            """)
    }

    /// What the pages on the board draw is in the model before they draw it. The notebook is
    /// moved away first, so anything still reaching for a file has nothing to reach for.
    @Test func aBoardBuiltFromASnapshotNeedsNoDisk() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let directory = tmp.appendingPathComponent("app")
        let root = NotebookFormat.root(in: directory)
        _ = try NotebookFormat.create(.project, title: "Console", in: root, project: nil)
        let task = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "console")
        try (try String(contentsOf: task, encoding: .utf8) + "\nHow the token is refreshed.\n")
            .write(to: task, atomically: true, encoding: .utf8)

        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)
        let card = try #require(project.snapshot.cards.first { $0.id == "wire-auth" })
        let console = try #require(project.snapshot.cards.first { $0.kind == .project })
        let repos = project.services(of: console)
        let summary = project.summary

        try FileManager.default.removeItem(at: directory)
        #expect(
            NotebookContent.sections(card.body)
                .contains { $0.blocks.contains(.paragraph("How the token is refreshed.")) },
            "a task page's text is the card's, not the file's")
        #expect(repos.map(\.repo) == ["app"] && repos.allSatisfy(\.exists), "and its repos were detected once")
        #expect(project.summary == summary, "and the summary is stored, not derived per read")
    }

    // `@AppStorage("openProjects")` is a string in defaults; relaunching reads it back.
    @Test func openProjectsRoundTripThroughDefaults() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let suite = "yongkang.test.open.\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let folders = try ["first", "moved", "second"].map { try notebook($0, in: tmp) }

        let app = AppModel()
        for folder in folders { _ = app.open(folder) }
        defaults.set(app.storedProjects, forKey: "openProjects")
        try FileManager.default.removeItem(at: folders[1])

        let relaunched = AppModel()
        relaunched.restore(try #require(defaults.string(forKey: "openProjects")))
        #expect(
            relaunched.projects.map(\.directory.path) == folders.map(\.path),
            "the same folders in the same order, the one moved away included")
        #expect(relaunched.projects.map(\.missing) == [false, true, false], "and only that one marked missing")
    }

    // Renamed in Terminal while open, and a dev server writes its cache back to the old path.
    @Test func aRenamedFolderIsMissingEvenWhenItsPathComesBack() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let folder = try notebook("site", in: tmp)
        let project = AppModel().open(folder)
        project.checkFolder()
        #expect(!project.missing)

        try FileManager.default.moveItem(at: folder, to: tmp.appendingPathComponent("renamed"))
        project.checkFolder()
        #expect(project.missing, "gone from its path")

        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("node_modules/.vite"), withIntermediateDirectories: true)
        project.checkFolder()
        #expect(project.missing, "and a new folder at that path is not the project")
    }
}
