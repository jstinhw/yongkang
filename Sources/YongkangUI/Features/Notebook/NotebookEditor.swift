import AppKit
import SwiftUI
import YongkangCore

/// Raw Markdown editing. Deliberately not a rendered preview: the agents in the
/// other sessions edit these same files, and frontmatter is the part you check.
struct NotebookEditor: View {
    let entry: NotebookEntry
    /// The window's alert rather than the editor's own: leaving the page saves it, and a save
    /// that fails then has no editor left to show why.
    @Binding var alert: AlertItem?

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
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.console)
                Button(action: save) { Label("Save", systemImage: "arrow.down.doc") }
                    .buttonStyle(.consolePrimary)
                    .keyboardShortcut("s")
                    .disabled(!isPage || text == loaded)
            }
        }
        .background(Theme.bg)
        .task { await load() }
        .onDisappear(perform: save)
    }

    private var isPage: Bool { entry.url.pathExtension == "md" }

    /// The raw file, not the card's body: this box edits the frontmatter too. Read off the
    /// main actor, and dropped if the page was closed while the disk answered.
    private func load() async {
        let url = entry.url
        let fresh = await Task.detached { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }.value
        guard !Task.isCancelled else { return }
        text = fresh
        loaded = fresh
    }

    private func save() {
        guard isPage, text != loaded else { return }
        if let problem = Self.save(text, over: loaded, to: entry.url) {
            alert = problem
        } else {
            loaded = text
        }
    }

    /// Writes `text` to `url` unless the file no longer holds `loaded`: an agent edited the page
    /// while it was open, and saving would overwrite that. Nil when it was saved.
    static func save(_ text: String, over loaded: String, to url: URL) -> AlertItem? {
        do {
            guard try String(contentsOf: url, encoding: .utf8) == loaded else {
                return .message(
                    "This page changed while you were editing",
                    detail: "Your text is still here and was not saved. "
                        + "Copy it, then reopen the page to merge the agent's changes.")
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return .error(error)
        }
    }
}
