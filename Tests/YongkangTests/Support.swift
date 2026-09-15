import Foundation

/// A fresh directory under the temp dir. Pair with `defer { try? FileManager.default.removeItem(at: dir) }`.
func makeTemporaryDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("yongkang-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// The contents of `Fixtures/<path>`, e.g. `fixture("codex/trust-screen.ansi")`.
func fixture(_ path: String) throws -> String {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(path)", withExtension: nil) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
    }
    return try String(contentsOf: url, encoding: .utf8)
}
