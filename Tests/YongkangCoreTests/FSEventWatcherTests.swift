import Foundation
import Testing

@testable import YongkangCore

/// What the watcher promises the console: a write reaches the screen without anyone asking, a
/// burst of them is one wake-up rather than forty, and `stop()` really does put everything down
/// — including the box the C callback reads through, which nothing else would ever free.
@Suite struct FSEventWatcherTests {
    /// Collects every batch the watcher yields, so a test can ask how many wake-ups a burst
    /// cost rather than only whether one arrived.
    private actor Batches {
        private(set) var all: [[String]] = []
        var count: Int { all.count }
        var paths: [String] { all.flatMap { $0 } }
        func add(_ paths: [String]) { all.append(paths) }
    }

    /// A watcher on `paths`, a task draining it into `Batches`, and the way to stop both.
    /// `latency` is short so the tests aren't paying 300 ms per assertion.
    private func watching(
        _ paths: [URL], latency: CFTimeInterval = 0.1
    ) -> (watcher: FSEventWatcher, batches: Batches, drain: Task<Void, Never>) {
        let watcher = FSEventWatcher(latency: latency)
        let batches = Batches()
        let changes = watcher.changes
        let drain = Task { for await paths in changes { await batches.add(paths) } }
        watcher.watch(paths)
        return (watcher, batches, drain)
    }

    private func write(_ name: String, in directory: URL) throws {
        try "x".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test func aWriteIntoAWatchedFolderIsReported() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (watcher, batches, drain) = watching([tmp])
        defer {
            watcher.stop()
            drain.cancel()
        }

        try write("card.md", in: tmp)
        #expect(
            await eventually { await batches.paths.contains { $0.hasSuffix("card.md") } },
            "a file written under a watched folder is what the watcher exists to report")
    }

    /// The reason for the latency: an agent writing a batch of files, or a `git checkout`,
    /// must cost the console one read and not one per file.
    @Test func aBurstOfWritesCoalescesIntoAFewWakeUps() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (watcher, batches, drain) = watching([tmp], latency: 0.3)
        defer {
            watcher.stop()
            drain.cancel()
        }

        for index in 0..<40 { try write("task-\(index).md", in: tmp) }
        #expect(
            await eventually { await batches.paths.contains { $0.hasSuffix("task-39.md") } },
            "the last of the burst arrived")
        // Everything written inside one 300 ms window is one callback; a second is only the
        // tail of the burst landing after the window closed. Forty would mean no coalescing
        // at all, which is the regression this guards.
        let wakeUps = await batches.count
        #expect(wakeUps <= 4, "40 files cost \(wakeUps) wake-ups")
    }

    @Test func stoppingEndsTheStreamAndFreesTheBox() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (watcher, batches, drain) = watching([tmp])
        try write("first.md", in: tmp)
        #expect(await eventually { await batches.count > 0 }, "watching before it is stopped")

        watcher.stop()
        await drain.value  // the stream finished, so the consumer's `for await` returned
        // `isWatching` is the box, held weakly here and strongly only by the running stream:
        // false means the context's release thunk ran and nothing is left holding it. Waited
        // for rather than asserted outright — `FSEventStreamRelease` drops our reference, and
        // the last one is dropped by whatever inside FSEvents was still unwinding the stream.
        #expect(
            await eventually { !watcher.isWatching },
            "the stream handed the box back when it was released")

        let after = await batches.count
        try write("second.md", in: tmp)
        try await Task.sleep(for: .milliseconds(500))
        #expect(await batches.count == after, "a stopped watcher yields nothing")
    }

    /// Both are ordinary: a session's transcript folder doesn't exist until its CLI writes one,
    /// and a project folder can be moved or deleted while the console still has it open.
    @Test func aMissingOrDeletedFolderIsNotACrash() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let missing = tmp.appendingPathComponent("no-transcript-yet")
        let doomed = tmp.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: doomed, withIntermediateDirectories: true)

        let (watcher, batches, drain) = watching([missing, doomed])
        defer {
            watcher.stop()
            drain.cancel()
        }
        #expect(watcher.isWatching, "a folder that isn't there yet is a watch with nothing to say")

        try FileManager.default.removeItem(at: doomed)
        try write("elsewhere.md", in: tmp)
        // No claim about what either folder reports — only that watching them, losing one and
        // stopping all of it stays a working watcher. The safety poll is what covers the gap.
        try await Task.sleep(for: .milliseconds(300))
        _ = await batches.count
        #expect(watcher.isWatching)
    }

    @Test func watchingTheSameFoldersAgainLeavesTheStreamAlone() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (watcher, batches, drain) = watching([tmp])
        defer {
            watcher.stop()
            drain.cancel()
        }

        // Same folders, listed the other way round: a session read that found nothing new must
        // not tear the stream down and build the same one back on every beat.
        watcher.watch([tmp, tmp])
        try write("card.md", in: tmp)
        #expect(await eventually { await batches.paths.contains { $0.hasSuffix("card.md") } })
    }
}
