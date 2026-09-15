import Foundation

guard let path = CommandLine.arguments.dropFirst().first else {
    print("usage: swift run shots <dir>")
    exit(1)
}
// Top-level code runs on the main thread, but Swift 5 mode doesn't treat it as the main actor.
MainActor.assumeIsolated { DesignShots.run(into: URL(fileURLWithPath: path)) }
