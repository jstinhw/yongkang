import SwiftUI
import AppKit

/// Raw Markdown editing. Deliberately not a rendered preview: the agents in the
/// other sessions edit these same files, and frontmatter is the part you check.
struct NotebookEditor: View {
    let entry: NotebookEntry

    @State private var text = ""
    @State private var loaded = ""

    var body: some View {
        Group {
            if isPage {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
            } else {
                Text("Folder — open a page inside it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task { load() }
        .onDisappear(perform: save)
        .toolbar {
            ToolbarItemGroup {
                Button("Save", systemImage: "arrow.down.doc", action: save)
                    .keyboardShortcut("s")
                    .disabled(!isPage || text == loaded)
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                }
            }
        }
    }

    private var isPage: Bool { entry.url.pathExtension == "md" }

    private func load() {
        text = (try? String(contentsOf: entry.url, encoding: .utf8)) ?? ""
        loaded = text
    }

    private func save() {
        guard isPage, text != loaded else { return }
        do {
            let disk = try String(contentsOf: entry.url, encoding: .utf8)
            guard !Self.hasConflict(loaded: loaded, disk: disk) else {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "This page changed while you were editing"
                alert.informativeText = "Your text is still here and was not saved. Copy it, then reopen the page to merge the agent's changes."
                alert.runModal()
                return
            }
            try text.write(to: entry.url, atomically: true, encoding: .utf8)
            loaded = text
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func hasConflict(loaded: String, disk: String) -> Bool { loaded != disk }
}
