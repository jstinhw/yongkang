import SwiftUI
import AppKit

@main
struct ClaudeCodeApp: App {
    // ponytail: starts empty on purpose. Defaulting to $HOME made claude scan the home
    // folder and trip every TCC prompt (iCloud Drive, Music, Documents) at launch.
    // A folder chosen in NSOpenPanel carries user intent, so macOS grants it silently.
    @State private var directory: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let directory {
                    ClaudeTerminal(directory: directory)
                        .id(directory) // new directory = fresh session
                } else {
                    Button("Choose a project folder…") { directory = pickDirectory() }
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 700, minHeight: 440)
            .toolbar {
                ToolbarItem {
                    Button(directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Open…") {
                        if let picked = pickDirectory() { directory = picked }
                    }
                    .help(directory ?? "Choose a project folder")
                }
            }
        }
        .windowToolbarStyle(.unified)
    }
}

private func pickDirectory() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Claude Code will run in this folder."
    return panel.runModal() == .OK ? panel.url?.path : nil
}
