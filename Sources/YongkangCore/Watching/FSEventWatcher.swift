import CoreServices
import Foundation

/// Watches a handful of folders and says when something under them was written. One per open
/// project: the project's own tree, which is where `.notebook/` and everything git diffs live,
/// and the folder each live session's CLI keeps its transcript in, which is under the CLI's
/// home and not in the project at all.
///
/// This replaces the 2 s timer that used to re-list every project on every tick whether or not
/// anything had moved. An idle Mac now costs nothing but the 30 s safety poll behind this
/// (`AppModel.start(polling:)`), which is there because FSEvents does drop events — network
/// volumes, sleep — and "the board didn't update" would be a miserable bug to reproduce.
///
/// Deliberately **not** `Sendable` and not an actor. `FSEventStreamRef` is non-Sendable CF that
/// has to be created and torn down on one queue, so the watcher stays inside its owner's
/// isolation — a `@MainActor ProjectModel` — and everything it hands out is a value or the
/// `AsyncStream` below. What actually crosses into the C callback is `FSEventBox`, which holds
/// one `Sendable` value and nothing else.
package final class FSEventWatcher {
    /// The paths written under a watched folder, already coalesced by FSEvents' own latency.
    ///
    /// `.bufferingNewest(1)`: a consumer re-reads from disk anyway, so what it needs to know is
    /// *that* something changed. A backlog of bursts would only make it re-read what it has
    /// already read, which is the pile-up `ProjectModel`'s in-flight guards exist to prevent.
    package let changes: AsyncStream<[String]>
    private let continuation: AsyncStream<[String]>.Continuation

    /// Every `FSEventStream*` call happens here, and so does the callback. Never a run loop
    /// source: on the main run loop that would put the callback back on the main thread, which
    /// is the one place PR 4.2 took the disk out of.
    private let queue = DispatchQueue(label: "ai.yongkang.fsevents", qos: .utility)
    private var stream: FSEventStreamRef?
    /// Weak on purpose. The running stream owns the box — `Unmanaged.passRetained` into the
    /// context, handed back by the context's `release` thunk — and this is only how `stop()`
    /// can be checked to have really given it up. See `isWatching`.
    private weak var box: FSEventBox?
    /// What `watch(_:)` was last given, so being asked for the same folders again leaves the
    /// running stream alone rather than tearing one down and building the same one back.
    private var watched: [String] = []

    /// Never delivered. `.git/objects` is rewritten by every git command an agent runs and none
    /// of it changes what `git status` says, so it is excluded at the stream rather than
    /// filtered after the fact. Fixed for the watcher's life, because a project's `.git` is.
    private let excluded: [String]
    /// How long FSEvents holds events back so a burst arrives as one callback. 300 ms is long
    /// enough that a `git checkout` or an agent writing twenty files is one reload, and short
    /// enough that a card turning done is on screen before you have finished reading the line.
    private let latency: CFTimeInterval

    /// `excluding` are folders under the watched paths whose writes are noise; at most 8, which
    /// is all `FSEventStreamSetExclusionPaths` accepts. `latency` is only moved by the tests.
    package init(excluding: [URL] = [], latency: CFTimeInterval = 0.3) {
        self.excluded = excluding.prefix(8).map(\.path)
        self.latency = latency
        (changes, continuation) = AsyncStream.makeStream(
            of: [String].self, bufferingPolicy: .bufferingNewest(1))
    }

    /// Whether a stream is running. False before the first `watch(_:)` and after `stop()` — and
    /// because the box is held weakly here and strongly only by the stream, false also means the
    /// box the C callback reads through has been released.
    package var isWatching: Bool { box != nil }

    /// Watches exactly `paths` from now on, replacing whatever was being watched before.
    /// Asking for the folders already being watched does nothing at all.
    ///
    /// A folder that doesn't exist yet is not an error: FSEvents simply has nothing to report
    /// for it, and the safety poll covers the gap until the next `watch(_:)` after it appears.
    package func watch(_ paths: [URL]) {
        let wanted = Set(paths.map(\.path)).sorted()
        guard wanted != watched else { return }
        watched = wanted
        // `sync`, so every FSEventStream* call is made on the stream's own queue and the C
        // callback can never be mid-flight while the stream under it is torn down. It blocks
        // the caller — the main actor — for as long as fseventsd takes to register a handful of
        // paths, which is why this runs when a project opens or a session starts and never on a
        // beat. ponytail: if that ever shows up in a trace, the fix is a Sendable holder for the
        // stream and an async hop, not a run loop source.
        queue.sync {
            teardown()
            guard !wanted.isEmpty else { return }
            let box = FSEventBox(continuation)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(box).toOpaque(),
                retain: nil,
                // The stream owns the box from here: this hands it back when the stream is
                // released, which is the only thing that ever frees it.
                release: { Unmanaged<FSEventBox>.fromOpaque($0!).release() },
                copyDescription: nil)
            let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
            guard
                let stream = FSEventStreamCreate(
                    nil, Self.callback, &context, wanted as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, UInt32(flags))
            else {
                // Nothing took the retain above, so nothing would ever give it back.
                Unmanaged<FSEventBox>.fromOpaque(context.info!).release()
                Log.notebook.error(
                    "FSEventStreamCreate refused \(wanted.count, privacy: .public) paths: safety poll only")
                return
            }
            if !excluded.isEmpty { FSEventStreamSetExclusionPaths(stream, excluded as CFArray) }
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            self.stream = stream
            self.box = box
        }
    }

    /// Ends the watch and finishes `changes`, so a consumer's `for await` returns.
    ///
    /// Explicit, and called by the owner when the project is closed or the app quits, rather
    /// than `deinit`: a `@MainActor` owner's `deinit` is nonisolated and could not touch any of
    /// this, and `isolated deinit` needs macOS 15 while the app targets 14.
    ///
    /// One way. `changes` is finished for good, so `watch(_:)` after this would run a stream
    /// nobody can hear. A folder that is opened again gets a new `ProjectModel` and a new
    /// watcher with it, which is the only way back.
    package func stop() {
        watched = []
        queue.sync { teardown() }
        continuation.finish()
    }

    /// On `queue`, always. Stop, then invalidate — which is what guarantees no further callback
    /// — then release, which runs the context's `release` thunk and frees the box.
    private func teardown() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// `@convention(c)`, so it captures nothing and everything it knows arrives through `info`.
    /// It copies the paths into `[String]` values and yields them; it reads no file and holds
    /// no state of its own.
    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let box = Unmanaged<FSEventBox>.fromOpaque(info).takeUnretainedValue()
        // Paths, never contents: this callback fires for every file an agent writes, and what
        // is in those files is the user's work. See `Log`.
        let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
        // FSEvents fell behind, or is telling us its history is no longer trustworthy. Nothing
        // is lost — the consumer re-reads from disk and the safety poll is behind it — but this
        // is exactly the condition that would otherwise make a stale board impossible to
        // explain afterwards.
        let lost = UInt32(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped)
        if (0..<count).contains(where: { flags[$0] & lost != 0 }) {
            Log.notebook.notice("FSEvents dropped events; the next read is a full one anyway")
        }
        box.continuation.yield(changed)
    }
}

/// What the C callback reads back out of `FSEventStreamContext.info`. It holds one thing, and
/// that thing is a `Sendable` value type, so the box is genuinely `Sendable` — no `@unchecked`,
/// no lock, nothing for a second thread to tear.
private final class FSEventBox: Sendable {
    let continuation: AsyncStream<[String]>.Continuation

    init(_ continuation: AsyncStream<[String]>.Continuation) {
        self.continuation = continuation
    }
}
