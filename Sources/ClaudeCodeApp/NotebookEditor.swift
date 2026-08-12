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

    // ponytail: last write wins. Only touches disk when you actually typed, so an
    // agent's edits survive a look-but-don't-touch visit. Add an mtime check if
    // humans and agents start editing the same file at the same second.
    private func save() {
        guard isPage, text != loaded else { return }
        do {
            try text.write(to: entry.url, atomically: true, encoding: .utf8)
            loaded = text
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
