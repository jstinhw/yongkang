import Foundation

/// One notebook entry with its frontmatter read. The sidebar shows slugs; the board
/// needs the parts that describe relationships.
package struct NotebookCard: Identifiable, Equatable, Sendable {
    package let id: String
    package let url: URL
    package let kind: EntryKind
    package let title: String
    /// What the file says, until `NotebookIndex.settled` has an agent's word against it.
    package var status: String
    package let project: String?
    package let dependsOn: [String]
    /// Projects only: the folders this work lands in, so the board can say what it touches
    /// and the run button knows what to start. Empty means the project folder itself.
    var repos: [String] = []
    package var roadmap: String? = nil
    package var subject: String? = nil
    package var memoryType: String = ""
    package var result: String = ""
    /// Tasks only: the roster member designing this task. Non-empty is the whole rule for
    /// "this is a design task" — the one the engineering tasks on its screen wait on. The
    /// app never infers it from the title, the repo or the wording of the criteria,
    /// because a guess that is wrong either stalls plumbing behind a demo or lets a screen
    /// be built before anyone saw it.
    package var designer: String = ""
    /// The page's Markdown after its frontmatter, kept by the read that parsed the rest of
    /// this card. A screen showing a card's text reads it from here: opening the file again
    /// while it draws would put the disk back in the render loop.
    package var body: String = ""

    package init(
        id: String,
        url: URL,
        kind: EntryKind,
        title: String,
        status: String,
        project: String?,
        dependsOn: [String],
        repos: [String] = [],
        roadmap: String? = nil,
        subject: String? = nil,
        memoryType: String = "",
        result: String = "",
        designer: String = "",
        body: String = ""
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.title = title
        self.status = status
        self.project = project
        self.dependsOn = dependsOn
        self.repos = repos
        self.roadmap = roadmap
        self.subject = subject
        self.memoryType = memoryType
        self.result = result
        self.designer = designer
        self.body = body
    }

    package var isDesignWork: Bool { !designer.isEmpty }
}

package enum NotebookIndex {
    package static func visible(_ cards: [NotebookCard], showDone: Bool) -> [NotebookCard] {
        showDone ? cards : cards.filter { $0.status != "done" }
    }

    /// The cards as they read now rather than as the files say. `status: active` means an
    /// agent is on it, and only the agent ever writes that field, so a session that was
    /// killed — by a quit, a crash, or being closed — never gets to unset it: the task would
    /// read as worked-on for good, with nothing running. A task no live session holds is
    /// handed its queue status back, once here, rather than in every screen that draws one.
    ///
    /// `blocked` is the other way a file can be out of date: an agent that filed a gate and
    /// wrote `done` in the same run left work only the user can finish, and a done task
    /// drops off the board, out of the summary and into a commit message. An open block
    /// outranks the word in the file until the user settles it.
    ///
    /// Tasks only. A project card's `active` is about its own tasks, which `assigned` says
    /// nothing about.
    package static func settled(
        _ cards: [NotebookCard], assigned: Set<String>, blocked: Set<String>
    ) -> [NotebookCard] {
        func status(of card: NotebookCard) -> String? {
            guard card.kind == .task else { return nil }
            if blocked.contains(card.id) { return card.status == "blocked" ? nil : "blocked" }
            return card.status == "active" && !assigned.contains(card.id) ? "todo" : nil
        }
        // The common case is that nothing is stale, and this is read from view bodies.
        guard cards.contains(where: { status(of: $0) != nil }) else { return cards }
        return cards.map { card in
            guard let settled = status(of: card) else { return card }
            var card = card
            card.status = settled
            return card
        }
    }

    /// A project is finished when its own status says so, or when every task filed under
    /// it is done — the agent sets each task's status as it checks it off, and
    /// nothing ever goes back to write the project's, so the last task is the signal.
    package static func isFinished(_ project: NotebookCard, in cards: [NotebookCard]) -> Bool {
        if project.status == "done" { return true }
        let tasks = cards.filter { $0.kind == .task && $0.project == project.id }
        return !tasks.isEmpty && tasks.allSatisfy { $0.status == "done" }
    }

    package static func load(root: URL) -> [NotebookCard] {
        NotebookLoader.pages(NotebookLoader.loadAll(root: root)).compactMap(card(at:))
    }

    static func card(at url: URL) -> NotebookCard? {
        guard let text = Log.contents(of: url) else { return nil }
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
            repos: list(fields["repos"] ?? ""),
            roadmap: fields["roadmap"].flatMap { $0.isEmpty ? nil : $0 },
            subject: fields["subject"].flatMap { $0.isEmpty ? nil : $0 },
            memoryType: fields["memory_type"] ?? "",
            result: fields["result"] ?? "",
            designer: fields["designer"] ?? "",
            body: body(text)
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

    /// A page's Markdown after its frontmatter block — what a project's detail page
    /// actually shows, as opposed to the raw file `NotebookEditor` edits.
    package static func body(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return text }
        return lines[(close + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func list(_ value: String) -> [String] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",")
            .map { unquoted($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'",
            value.last == first
        else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// The picked tasks plus every unfinished task they wait on, transitively. A project
    /// dependency expands to that project's unfinished tasks: project pages themselves
    /// cannot be assigned to an agent. A blocker is part of the job, not a question
    /// to put to the user. `excluding` keeps a task already claimed by another assigned
    /// session out of the batch, whether it was picked directly or would otherwise
    /// be pulled in as a blocker. A task already `done` is dropped the same way — there is
    /// nothing left to assign it to do.
    package static func withBlockers(
        _ picked: [NotebookCard], in cards: [NotebookCard],
        excluding assigned: Set<String> = []
    ) -> [NotebookCard] {
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Keep task and unknown ids as written, but turn an unfinished project into the
        // concrete task ids that can finish it. If a project has no work to assign, leave
        // its id visible so the agent can report the inconsistent notebook instead of
        // silently treating it as complete.
        func concrete(_ ids: [String], visiting: Set<String> = []) -> [String] {
            var result: [String] = []
            for id in ids {
                guard let card = byID[id], card.kind == .project else {
                    result.append(id)
                    continue
                }
                guard card.status != "done" else { continue }
                guard !visiting.contains(id) else {
                    result.append(id)
                    continue
                }
                let tasks = cards.filter {
                    $0.kind == .task && $0.project == id && $0.status != "done"
                }.map(\.id)
                let expanded = concrete(card.dependsOn + tasks, visiting: visiting.union([id]))
                result.append(contentsOf: expanded.isEmpty ? [id] : expanded)
            }
            var seen: Set<String> = []
            return result.filter { seen.insert($0).inserted }
        }

        func normalized(_ card: NotebookCard) -> NotebookCard {
            let dependencies = concrete(card.dependsOn)
            guard dependencies != card.dependsOn else { return card }
            return NotebookCard(
                id: card.id, url: card.url, kind: card.kind, title: card.title,
                status: card.status, project: card.project, dependsOn: dependencies,
                repos: card.repos, roadmap: card.roadmap, subject: card.subject,
                memoryType: card.memoryType, result: card.result,
                designer: card.designer, body: card.body)
        }

        let eligible = picked.filter { $0.status != "done" && !assigned.contains($0.id) }
        var chosen = Set(eligible.map(\.id))
        var queue = eligible

        while let card = queue.popLast() {
            for id in concrete(card.dependsOn) {
                guard !chosen.contains(id), !assigned.contains(id), let blocker = byID[id],
                    blocker.kind == .task, blocker.status != "done"
                else { continue }
                chosen.insert(id)
                queue.append(blocker)
            }
        }
        return ordered(cards.filter { chosen.contains($0.id) }.map(normalized))
    }

    package static func ordered(_ subset: [NotebookCard]) -> [NotebookCard] {
        waves(subset).flatMap { $0 }
    }

    /// The batch split into what can be worked on at the same time: tasks joined by
    /// `depends_on` — directly, or through another task in the batch — stay together, because
    /// one cannot start while its blocker is still being written next door. Each group comes
    /// back in build order, and the groups in the order their first task would start.
    // ponytail: a walk over the edges, no union-find. A batch is a handful of cards.
    package static func chains(_ subset: [NotebookCard]) -> [[NotebookCard]] {
        let byID = Dictionary(subset.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var joined: [String: Set<String>] = [:]
        for card in subset {
            for blocker in card.dependsOn where byID[blocker] != nil {
                joined[card.id, default: []].insert(blocker)
                joined[blocker, default: []].insert(card.id)
            }
        }
        var seen: Set<String> = []
        var groups: [[NotebookCard]] = []
        for card in ordered(subset) where seen.insert(card.id).inserted {
            var group: [NotebookCard] = []
            var queue = [card.id]
            while let id = queue.popLast() {
                guard let found = byID[id] else { continue }
                group.append(found)
                for next in joined[id] ?? [] where seen.insert(next).inserted { queue.append(next) }
            }
            groups.append(ordered(group))
        }
        return groups
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
        if parts.contains("runs") { return .run }
        if parts.contains("roadmap") { return .roadmap }
        if parts.contains("tasks") { return .task }
        return .project
    }
}

extension NotebookIndex {
    /// The "Done when" boxes on a page, wherever they sit in it. This is the only progress
    /// a task actually records, so it is what the console draws — nothing is inferred.
    package static func checklist(at url: URL) -> [NotebookContent.ChecklistItem] {
        guard let text = Log.contents(of: url) else { return [] }
        return checklist(in: body(text))
    }

    /// The same, from a body a card already carries, so a screen can count it without the disk.
    package static func checklist(in body: String) -> [NotebookContent.ChecklistItem] {
        NotebookContent.sections(body).flatMap { section in
            section.blocks.flatMap { block -> [NotebookContent.ChecklistItem] in
                if case .checklist(let items) = block { return items }
                return []
            }
        }
    }

    /// A page's brief: the first paragraph of its body, which the format says is written for a
    /// human in one to three sentences.
    package static func brief(of body: String) -> String? {
        for section in NotebookContent.sections(body) {
            for block in section.blocks {
                if case .paragraph(let text) = block { return text }
            }
        }
        return nil
    }
}
