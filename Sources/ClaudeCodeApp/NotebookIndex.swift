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
    /// Projects only: the folders this work lands in, so the board can say what it touches
    /// and the run button knows what to start. Empty means the project folder itself.
    var repos: [String] = []
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
            dependsOn: list(fields["depends_on"] ?? ""),
            repos: list(fields["repos"] ?? "")
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
    /// is part of the job, not a question to put to the user. `excluding` keeps a task
    /// already claimed by another Engineering Lead session out of the batch, whether it
    /// was picked directly or would otherwise be pulled in as a blocker. A task already
    /// `done` is dropped the same way — there is nothing left to assign it to do.
    static func withBlockers(_ picked: [NotebookCard], in cards: [NotebookCard],
                             excluding assigned: Set<String> = []) -> [NotebookCard] {
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let eligible = picked.filter { $0.status != "done" && !assigned.contains($0.id) }
        var chosen = Set(eligible.map(\.id))
        var queue = eligible

        while let card = queue.popLast() {
            for id in card.dependsOn {
                guard !chosen.contains(id), !assigned.contains(id), let blocker = byID[id],
                      blocker.kind == .task, blocker.status != "done" else { continue }
                chosen.insert(id)
                queue.append(blocker)
            }
        }
        return ordered(cards.filter { chosen.contains($0.id) })
    }

    static func ordered(_ subset: [NotebookCard]) -> [NotebookCard] {
        waves(subset).flatMap { $0 }
    }

    /// The same sort, kept in levels: everything in a wave can start once the waves before
    /// it are done, which is what the board draws left to right.
    // ponytail: Kahn's with ties left in file order, O(n²) over a handful of cards. A
    // cycle stops the sort and lands the rest in one final wave rather than dropping any.
    static func waves(_ subset: [NotebookCard]) -> [[NotebookCard]] {
        let present = Set(subset.map(\.id))
        var remaining = subset
        var placed: Set<String> = []
        var result: [[NotebookCard]] = []

        while !remaining.isEmpty {
            let ready = remaining.filter { $0.dependsOn.filter(present.contains).allSatisfy(placed.contains) }
            guard !ready.isEmpty else { return result + [remaining] }
            result.append(ready)
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
