import Foundation

/// A fresh directory under the temp dir. Pair with `defer { try? FileManager.default.removeItem(at: dir) }`.
func makeTemporaryDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("yongkang-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// The contents of `Fixtures/<path>`, e.g. `fixture("codex/trust-screen.ansi")`. The fixtures
/// live once, in YongkangCoreTests, so this target reads them from the checkout beside it.
func fixture(_ path: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../YongkangCoreTests/Fixtures/\(path)")
    return try String(contentsOf: url, encoding: .utf8)
}

/// True once `condition` holds, false if it still doesn't after `seconds`. Suspends between
/// checks instead of pumping `RunLoop.main`: a main-actor test is itself a main-queue job, so a
/// nested pump never runs the PTY reads queued behind it.
///
/// ponytail: a generous bound, not a timing claim. Other suites run on the main actor in
/// parallel, and a PTY read can queue behind whatever they are doing there. Neither git
/// (PR 4.1) nor the notebook reads (PR 4.2) hold it any more; tighten it if a run ever
/// shows how much slack is really left.
@MainActor
func eventually(within seconds: Double = 15, _ condition: () -> Bool) async throws -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        guard Date() < deadline else { return false }
        try await Task.sleep(for: .milliseconds(20))
    }
    return true
}
