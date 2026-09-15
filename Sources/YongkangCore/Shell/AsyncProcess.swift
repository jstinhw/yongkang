import Foundation

/// A child process that is awaited rather than waited on. `waitUntilExit()` holds its thread
/// until the child is gone, which on the main thread is a frozen window for as long as git
/// takes; here the exit arrives through `terminationHandler` and the caller only suspends.
package enum AsyncProcess {
    /// Where the child's stderr goes. `merge` shares stdout's pipe, so a failure that git
    /// explains half on stdout and half on stderr still reads in the order it was written.
    package enum Stderr: Sendable {
        case discard, capture, merge
    }

    package struct Output: Sendable {
        package let status: Int32
        package let stdout: Data
        /// Empty unless stderr was `capture`d.
        package let stderr: Data

        package var text: String { String(decoding: stdout, as: UTF8.self) }
    }

    /// Throws when the executable can't be started, and `CancellationError` when the calling
    /// task is cancelled, which terminates the child first.
    package static func run(
        _ executable: URL, _ arguments: [String], in directory: URL? = nil,
        environment: [String: String]? = nil, stderr: Stderr = .discard
    ) async throws -> Output {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        // Nothing here answers a prompt, so a child that asks for input reads EOF instead of
        // waiting on whatever stdin the app was launched with.
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = stderr == .capture ? Pipe() : nil
        process.standardOutput = out
        switch stderr {
        case .discard: process.standardError = FileHandle.nullDevice
        case .capture: process.standardError = err
        case .merge: process.standardError = out
        }
        let run = Run(process, pipes: [out] + (err.map { [$0] } ?? []))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { run.start($0) }
        } onCancel: {
            run.cancel()
        }
    }

    /// One launch's state, shared by the pipe readers, the termination handler and the
    /// cancellation handler, which all run on threads of their own.
    ///
    /// @unchecked: `lock` guards every stored property below it — Foundation hands these
    /// callbacks to us on its own threads, so there is no actor to isolate them to.
    private final class Run: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process
        private let pipes: [Pipe]
        private var buffers: [Data]
        /// Pipes not yet at EOF, plus one for the process until it exits. The result is only
        /// complete once all of them are done: a child can exit with output still in the pipe.
        private var pending: Int
        private var continuation: CheckedContinuation<Output, Error>?
        private var launched = false
        private var cancelled = false

        init(_ process: Process, pipes: [Pipe]) {
            self.process = process
            self.pipes = pipes
            buffers = pipes.map { _ in Data() }
            pending = pipes.count + 1
        }

        func start(_ continuation: CheckedContinuation<Output, Error>) {
            lock.withLock { self.continuation = continuation }
            // Drained while the child runs, not after: a pipe holds about 64 KB, and a child
            // that fills it blocks until someone reads, so reading only after exit deadlocks
            // on any output larger than that.
            for (index, pipe) in pipes.enumerated() {
                pipe.fileHandleForReading.readabilityHandler = { [self] handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty { handle.readabilityHandler = nil }
                    lock.withLock {
                        if chunk.isEmpty { pending -= 1 } else { buffers[index].append(chunk) }
                    }
                    finishIfDone()
                }
            }
            process.terminationHandler = { [self] exited in
                exited.terminationHandler = nil
                lock.withLock { pending -= 1 }
                finishIfDone()
            }
            do {
                try process.run()
            } catch {
                for pipe in pipes { pipe.fileHandleForReading.readabilityHandler = nil }
                process.terminationHandler = nil
                let waiting = lock.withLock {
                    defer { self.continuation = nil }
                    return self.continuation
                }
                waiting?.resume(throwing: error)
                return
            }
            lock.withLock {
                launched = true
                if cancelled { process.terminate() }
            }
        }

        /// `terminate()` before launch raises, so a cancellation that arrives first is only
        /// recorded, and `start` acts on it once the child exists.
        func cancel() {
            lock.withLock {
                cancelled = true
                if launched && process.isRunning { process.terminate() }
            }
        }

        private func finishIfDone() {
            let finished: (CheckedContinuation<Output, Error>, Result<Output, Error>)? = lock.withLock {
                guard pending == 0, let continuation else { return nil }
                self.continuation = nil
                let result: Result<Output, Error> =
                    cancelled
                    ? .failure(CancellationError())
                    : .success(
                        Output(
                            status: process.terminationStatus, stdout: buffers[0],
                            stderr: buffers.count > 1 ? buffers[1] : Data()))
                return (continuation, result)
            }
            guard let (continuation, result) = finished else { return }
            continuation.resume(with: result)
        }
    }
}
