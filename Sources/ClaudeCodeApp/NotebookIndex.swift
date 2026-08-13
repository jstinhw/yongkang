import Foundation

/// One notebook entry with its frontmatter read. The sidebar shows slugs; the board
/// needs the parts that describe relationships.
struct NotebookCard: Identifiable, Equatable {
    let id: String
    let url: URL
    let kind: EntryKind
    let title: String
    let status: String
    let project: String?
    let dependsOn: [String]
}

enum NotebookIndex {
    static func load(root: URL) -> [NotebookCard] {
        NotebookLoader.pages(NotebookLoader.load(root: root)).compactMap(card(at:))
    }

    static func card(at url: URL) -> NotebookCard? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fields = frontmatter(text)
        let stem = url.deletingPathExtension().lastPathComponent
        let kind = fields["kind"].flatMap(EntryKind.init(rawValue:)) ?? kind(from: url)
        return NotebookCard(
            id: fields["id"].flatMap { $0.isEmpty ? nil : $0 } ?? stem,
            url: url,
            kind: kind,
            title: fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? stem,
            status: fields["status"] ?? "",
            project: fields["project"].flatMap { $0.isEmpty ? nil : $0 },
            dependsOn: list(fields["depends_on"] ?? "")
        )
    }

    /// A flat `key: value` read of the leading `---` block. Not YAML: nested keys are
    /// flattened into the top level, which is harmless because only known keys are read.
    /// Block-style lists are not understood — the format documents inline `[a, b]`.
    static func frontmatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = unquoted(value) }
        }
        return fields
    }

    static func list(_ value: String) -> [String] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",")
            .map { unquoted($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'",
              value.last == first else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Fallback for a file whose frontmatter is missing or unreadable.
    private static func kind(from url: URL) -> EntryKind {
        let parts = url.pathComponents
        if parts.contains("memory") { return .memory }
        if parts.contains("roadmap") { return .roadmap }
        if parts.contains("tasks") { return .task }
        return .project
    }
}
