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
