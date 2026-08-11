import SwiftUI
import AppKit

@main
struct ClaudeCodeApp: App {
    // ponytail: starts empty on purpose. Defaulting to $HOME made claude scan the home
    // folder and trip every TCC prompt (iCloud Drive, Music, Documents) at launch.
    // A folder chosen in NSOpenPanel carries user intent, so macOS grants it silently.
    @State private var sessions: [CodeSession] = []
    @State private var selection: UUID?

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(sessions, selection: $selection) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(session.name, systemImage: session.agent.systemImage)
                        Text("\(session.agent.displayName) · \(session.directory)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("Close Session") { close(session.id) }
                    }
                }
                .navigationTitle("Sessions")
                .toolbar {
                    ToolbarItemGroup {
                        newSessionMenu
                            .keyboardShortcut("n")
                        Button("Close Session", systemImage: "minus") {
                            if let selection { close(selection) }
                        }
                        .disabled(selection == nil)
                    }
                }
            } detail: {
                ZStack {
                    if sessions.isEmpty {
                        newSessionMenu
                            .controlSize(.large)
                    }
                    // Keep every terminal mounted so switching rows does not restart the agent.
                    ForEach(sessions) { session in
                        AgentTerminal(directory: session.directory, agent: session.agent)
                            .opacity(selection == session.id ? 1 : 0)
                            .allowsHitTesting(selection == session.id)
                            .accessibilityHidden(selection != session.id)
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 440)
        }
        .windowToolbarStyle(.unified)
    }

    private var newSessionMenu: some View {
        Menu("New Session", systemImage: "plus") {
            Button("Claude Code…", systemImage: AgentKind.claude.systemImage) {
                openSession(.claude)
            }
            Button("Codex…", systemImage: AgentKind.codex.systemImage) {
                openSession(.codex)
            }
        }
    }

    private func openSession(_ agent: AgentKind) {
        guard let directory = pickDirectory() else { return }
        let session = CodeSession(directory: directory, agent: agent)
        sessions.append(session)
        selection = session.id
    }

    private func close(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: index)
        if selection == id {
            selection = sessions.indices.contains(index) ? sessions[index].id : sessions.last?.id
        }
    }
}

private struct CodeSession: Identifiable {
    let id = UUID()
    let directory: String
    let agent: AgentKind
    var name: String { URL(fileURLWithPath: directory).lastPathComponent }
}

private func pickDirectory() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "The coding agent will run in this folder."
    return panel.runModal() == .OK ? panel.url?.path : nil
}
