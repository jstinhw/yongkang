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

    /// The picked tasks plus every unfinished task they wait on, transitively. A blocker
    /// is part of the job, not a question to put to the user.
    static func withBlockers(_ picked: [NotebookCard], in cards: [NotebookCard]) -> [NotebookCard] {
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var chosen = Set(picked.map(\.id))
        var queue = picked

        while let card = queue.popLast() {
            for id in card.dependsOn {
                guard !chosen.contains(id), let blocker = byID[id],
                      blocker.kind == .task, blocker.status != "done" else { continue }
                chosen.insert(id)
                queue.append(blocker)
            }
        }
        return ordered(cards.filter { chosen.contains($0.id) })
    }

    // ponytail: Kahn's with ties left in file order, O(n²) over a handful of cards. A
    // cycle stops the sort and appends the rest rather than dropping anything.
    static func ordered(_ subset: [NotebookCard]) -> [NotebookCard] {
        let present = Set(subset.map(\.id))
        var remaining = subset
        var placed: Set<String> = []
        var result: [NotebookCard] = []

        while !remaining.isEmpty {
            let ready = remaining.filter { $0.dependsOn.filter(present.contains).allSatisfy(placed.contains) }
            guard !ready.isEmpty else { return result + remaining }
            result.append(contentsOf: ready)
            placed.formUnion(ready.map(\.id))
            let readyIDs = Set(ready.map(\.id))
            remaining.removeAll { readyIDs.contains($0.id) }
        }
        return result
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
