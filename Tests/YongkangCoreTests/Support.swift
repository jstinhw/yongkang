import Foundation
import Testing

@testable import YongkangCore

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

/// Runs git for a test's own setup, and returns what it said. With the app's git environment,
/// so a test run from a git hook sets up its temp repo and never the checkout running the hook.
@discardableResult
func git(_ arguments: [String], in directory: URL) async throws -> String {
    let output = try await AsyncProcess.run(
        URL(fileURLWithPath: "/usr/bin/env"), ["git"] + arguments, in: directory,
        environment: GitClient.environment, stderr: .merge)
    try #require(output.status == 0, "git \(arguments.joined(separator: " ")) failed: \(output.text)")
    return output.text
}

/// `directory`, created if need be, as a repository with a committer on branch `main`.
func makeRepository(_ directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for arguments in [
        ["init", "--quiet", "--initial-branch=main"], ["config", "user.email", "test@example.com"],
        ["config", "user.name", "Test"],
    ] {
        try await git(arguments, in: directory)
    }
}
