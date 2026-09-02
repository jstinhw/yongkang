import SwiftUI
import AppKit

/// Raw Markdown editing. Deliberately not a rendered preview: the agents in the
/// other sessions edit these same files, and frontmatter is the part you check.
struct NotebookEditor: View {
    let entry: NotebookEntry

    @State private var text = ""
    @State private var loaded = ""

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isPage {
                    TextEditor(text: $text)
                        .font(Typo.mono(12))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                } else {
                    Text("Folder — open a page inside it.")
                        .font(Typo.text(13))
                        .foregroundStyle(Theme.tx3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ActionBar {
                Text(entry.url.lastPathComponent)
                    .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                if isPage && text != loaded {
                    NotebookStyle.pill("unsaved", Theme.amber)
                }
                Spacer(minLength: 12)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                } label: { Label("Reveal", systemImage: "folder") }
                    .buttonStyle(.console)
                Button(action: save) { Label("Save", systemImage: "arrow.down.doc") }
                    .buttonStyle(.consolePrimary)
                    .keyboardShortcut("s")
                    .disabled(!isPage || text == loaded)
            }
        }
        .background(Theme.bg)
        .task { load() }
        .onDisappear(perform: save)
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
