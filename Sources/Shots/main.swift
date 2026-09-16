import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first else {
    print("usage: swift run shots <dir>          # every screen, offscreen")
    print("       swift run shots --icon <file>  # the app icon's 1024 master")
    exit(1)
}
// Top-level code runs on the main thread, but Swift 5 mode doesn't treat it as the main actor.
MainActor.assumeIsolated {
    guard first == "--icon" else {
        return DesignShots.run(into: URL(fileURLWithPath: first))
    }
    guard let file = arguments.dropFirst().first else {
        print("usage: swift run shots --icon <file>")
        exit(1)
    }
    guard IconShot.write(to: URL(fileURLWithPath: file)) else { exit(1) }
}
