import Foundation
import Testing

@testable import YongkangCore

/// The process wrapper every git call goes through. What it has to survive is output bigger
/// than a pipe holds, and a caller that stops waiting.
@Suite struct AsyncProcessTests {
    private static let sh = URL(fileURLWithPath: "/bin/sh")

    @Test func returnsTheStatusAndWhatTheChildWrote() async throws {
        let output = try await AsyncProcess.run(Self.sh, ["-c", "printf out; printf err >&2; exit 3"])
        #expect(output.status == 3)
        #expect(output.text == "out")
        #expect(output.stderr.isEmpty, "stderr is dropped unless it is asked for")

        let merged = try await AsyncProcess.run(Self.sh, ["-c", "printf out; printf err >&2"], stderr: .merge)
        #expect(merged.text == "outerr", "merged, both streams arrive on stdout in the order written")
    }

    @Test func drainsOutputLargerThanAPipeHoldsOnBothStreams() async throws {
        // 1.1 MB on each stream, stderr first: a reader that only drained stdout, or only
        // read after exit, would leave the child blocked on a full pipe and never return.
        let script = "head -c 1126400 /dev/zero >&2; head -c 1126400 /dev/zero"
        let output = try await AsyncProcess.run(Self.sh, ["-c", script], stderr: .capture)
        #expect(output.status == 0)
        #expect(output.stdout.count == 1100 * 1024)
        #expect(output.stderr.count == 1100 * 1024)
    }

    @Test func cancellingTheCallerTerminatesTheChild() async throws {
        let started = Date()
        let waiting = Task { try await AsyncProcess.run(URL(fileURLWithPath: "/bin/sleep"), ["30"]) }
        try await Task.sleep(for: .milliseconds(200))
        waiting.cancel()
        let result = await waiting.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(
            Date().timeIntervalSince(started) < 10,
            "the call returns once the child is gone, which only a terminated sleep 30 is this soon")
    }

    @Test func aChildThatCannotStartThrows() async {
        await #expect(throws: (any Error).self) {
            try await AsyncProcess.run(URL(fileURLWithPath: "/nonexistent/tool"), [])
        }
    }
}
