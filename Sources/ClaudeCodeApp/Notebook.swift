import Foundation

/// One row in the notebook sidebar. `id` is the file path so selection and
/// disclosure survive the periodic reload after an agent writes a file.
struct NotebookEntry: Identifiable, Equatable {
    let id: String
    let url: URL
    let title: String
    let icon: String
    let children: [NotebookEntry]?

    /// Both sides of a selection must agree: FileManager hands back symlink-resolved
    /// URLs (/var → /private/var), a URL you just appended to keeps the symlink.
    static func id(for url: URL) -> String { url.resolvingSymlinksInPath().path }
}

enum NotebookLoader {
    /// Empty when the project has no `.notebook` — nothing is created to read it.
    static func load(root: URL) -> [NotebookEntry] {
        NotebookFormat.folders.compactMap { node(at: root.appendingPathComponent($0)) }
    }

    static func pageCount(_ entries: [NotebookEntry]) -> Int {
        entries.reduce(0) { total, entry in
            total + (entry.url.pathExtension == "md" ? 1 : 0) + pageCount(entry.children ?? [])
        }
    }

    static func find(_ id: String, in entries: [NotebookEntry]) -> NotebookEntry? {
        for entry in entries {
            if entry.id == id { return entry }
            if let hit = entry.children.flatMap({ find(id, in: $0) }) { return hit }
        }
        return nil
    }

    private static func node(at url: URL) -> NotebookEntry? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

        guard isDirectory.boolValue else {
            guard url.pathExtension == "md" else { return nil }
            return NotebookEntry(id: NotebookEntry.id(for: url), url: url,
                                 title: url.deletingPathExtension().lastPathComponent,
                                 icon: icon(for: url), children: nil)
        }

        let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let children = contents
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(node(at:))
        // A folder opens its own page when it has one, so projects/<id>/ selects project.md
        // and keeps only memory/ as a child row. `children == nil` means an actual file:
        // without it, projects/ adopts the rewritten url of the first project inside it.
        let page = children.first { $0.children == nil && $0.url.lastPathComponent == "project.md" }
        return NotebookEntry(id: NotebookEntry.id(for: url), url: page?.url ?? url,
                             title: url.lastPathComponent, icon: icon(for: url),
                             children: children.filter { $0.id != page?.id })
    }

    static func icon(forFolder folder: String) -> String {
        switch folder {
        case "roadmap": return "map"
        case "projects": return "shippingbox"
        case "tasks": return "checkmark.circle"
        default: return "doc.text"
        }
    }

    private static func icon(for url: URL) -> String {
        let parts = url.pathComponents
        if parts.contains("memory") { return "brain" }
        // `projects` before `tasks`, so a project someone named "tasks" still reads as one.
        for folder in NotebookFormat.folders where parts.contains(folder) {
            return icon(forFolder: folder)
        }
        return "doc.text"
    }
}
