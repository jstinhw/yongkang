import Foundation

package enum EntryKind: String, CaseIterable, Sendable {
    case roadmap, project, task, memory, run

    /// What the window calls it. A `project` entry is a milestone on screen, so it cannot be
    /// mistaken for the project folder that holds the whole notebook; the file keeps its name.
    package var displayName: String { self == .project ? "Milestone" : rawValue.capitalized }
}

enum NotebookError: LocalizedError {
    case emptyTitle
    case missingProject

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Give the entry a title."
        case .missingProject: return "Pick a milestone first — memory lives inside one."
        }
    }
}

/// On-disk shape of a notebook. Everything here is plain Markdown so the coding
/// agents running in the sidebar read and write it with no extra plumbing.
package enum NotebookFormat {
    package static let folderName = ".notebook"
    static let specFile = "NOTEBOOK.md"
    static let folders = ["roadmap", "projects", "tasks", "runs"]
    static let visibleFolders = ["roadmap", "projects", "tasks"]

    /// Where a project keeps its notebook. Nothing is written until the first entry:
    /// a project with no `.notebook` stays untouched and simply reads as empty.
    package static func root(in project: URL) -> URL { project.appendingPathComponent(folderName) }

    private static func scaffold(_ root: URL) throws {
        let fm = FileManager.default
        for sub in folders {
            try fm.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let spec = root.appendingPathComponent(specFile)
        if !fm.fileExists(atPath: spec.path) {
            try specText.write(to: spec, atomically: true, encoding: .utf8)
        }
    }

    package static func create(
        _ kind: EntryKind, title: String, in root: URL, project: String?,
        roadmap: String? = nil, subject: String? = nil
    ) throws -> URL {
        let base = slug(title)
        try scaffold(root)
        guard !base.isEmpty else { throw NotebookError.emptyTitle }
        let fm = FileManager.default
        let day = today()

        switch kind {
        case .roadmap:
            let file = unique(root.appendingPathComponent("roadmap/\(base).md"))
            return try write(file, id: base, kind: kind, title: title, project: nil, day: day)

        case .task:
            let file = unique(root.appendingPathComponent("tasks/\(base).md"))
            return try write(
                file, id: file.deletingPathExtension().lastPathComponent,
                kind: kind, title: title, project: project, day: day)

        case .project:
            var dir = root.appendingPathComponent("projects/\(base)")
            var n = 2
            while fm.fileExists(atPath: dir.path) {
                dir = root.appendingPathComponent("projects/\(base)-\(n)")
                n += 1
            }
            try fm.createDirectory(at: dir.appendingPathComponent("memory"), withIntermediateDirectories: true)
            return try write(
                dir.appendingPathComponent("project.md"), id: dir.lastPathComponent,
                kind: kind, title: title, project: nil, roadmap: roadmap, day: day)

        case .memory:
            guard let project, !project.isEmpty else { throw NotebookError.missingProject }
            let dir = root.appendingPathComponent("projects/\(project)/memory")
            let file = unique(dir.appendingPathComponent("\(day)-\(base).md"))
            return try write(
                file, id: file.deletingPathExtension().lastPathComponent,
                kind: kind, title: title, project: project,
                subject: subject ?? project, day: day)

        case .run:
            let file = unique(root.appendingPathComponent("runs/\(timestamp())-\(base).md"))
            return try write(
                file, id: file.deletingPathExtension().lastPathComponent,
                kind: kind, title: title, project: project,
                subject: subject ?? project, day: day)
        }
    }

    /// Everything one entry owns on disk. A project is a folder — its page and its
    /// memory — plus the tasks filed under it, which live in `tasks/` and would otherwise
    /// be left pointing at an id that is gone.
    package static func owned(by card: NotebookCard, in cards: [NotebookCard]) -> [URL] {
        guard card.kind == .project else { return [card.url] }
        let folder = card.url.deletingLastPathComponent()
        return [folder] + cards.filter { $0.kind == .task && $0.project == card.id }.map(\.url)
    }

    /// Trash, not erase: a notebook page is the user's own writing, so removing one stays
    /// undoable from the Finder. A volume with no trash falls back to a plain delete. Tests
    /// pass `trash: false` so every run doesn't leave pages in the developer's Trash.
    package static func remove(_ card: NotebookCard, in cards: [NotebookCard], trash: Bool = true) throws {
        let fm = FileManager.default
        for url in owned(by: card, in: cards) where fm.fileExists(atPath: url.path) {
            if trash, (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil { continue }
            try fm.removeItem(at: url)
        }
    }

    package static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { ch in ch.isASCII && (ch.isLetter || ch.isNumber) ? ch : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }

    // MARK: - Writing

    private static func write(
        _ file: URL, id: String, kind: EntryKind,
        title: String, project: String?, roadmap: String? = nil,
        subject: String? = nil, day: String
    ) throws -> URL {
        var fields: [(String, String)] = [
            ("id", id),
            ("kind", kind.rawValue),
            ("title", yaml(title)),
        ]
        if kind != .memory && kind != .run { fields.append(("status", "todo")) }
        if kind == .project { fields.append(("roadmap", roadmap ?? "")) }
        if kind == .task || kind == .memory || kind == .run {
            fields.append(("project", project ?? ""))
        }
        if kind == .memory || kind == .run { fields.append(("subject", subject ?? "")) }
        if kind != .memory && kind != .run {
            fields.append(("depends_on", "[]"))
            fields.append(("owner", "\"\""))
        }
        if kind == .project { fields.append(("repos", "[]")) }
        if kind == .memory {
            fields.append(contentsOf: [
                ("memory_type", "note"), ("source", "user"),
                ("supersedes", "[]"),
            ])
        }
        if kind == .run {
            fields.append(contentsOf: [
                ("result", "partial"), ("agent", "\"\""),
                ("started", "\"\""), ("ended", "\"\""),
            ])
        }
        fields.append(contentsOf: [("created", day), ("updated", day), ("external", "{}")])

        let front = fields.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        let text = "---\n\(front)\n---\n\n\(body(for: kind))"
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// The one status the app sets on a task, and only because the user threw its work away:
    /// `status: todo`, so the board offers it to an agent again. The status line in the
    /// frontmatter and nothing else in the file, like resolving a block by hand.
    package static func reopen(_ task: URL) throws {
        let text = try String(contentsOf: task, encoding: .utf8)
        let front = text.range(
            of: "\n---",
            range: text.index(text.startIndex, offsetBy: 3, limitedBy: text.endIndex)
                .map { $0..<text.endIndex })
        guard text.hasPrefix("---"), let front,
            let line = text.range(
                of: #"\nstatus:[^\n]*"#, options: .regularExpression, range: text.startIndex..<front.lowerBound)
        else { return }
        try text.replacingCharacters(in: line, with: "\nstatus: todo").write(
            to: task, atomically: true, encoding: .utf8)
    }

    private static func body(for kind: EntryKind) -> String {
        switch kind {
        case .roadmap:
            return "## Goal\n\n## Bets\n\n## Not doing\n"
        case .project:
            return "## Outcome\n\n## Approach\n\n## Open questions\n"
        case .task:
            return "## Done when\n\n- [ ] \n"
        case .memory:
            return "The fact or decision, and why it went that way.\n"
        case .run:
            return
                "What changed and what the next agent needs to know.\n\n## Handoff\n\n## Completed\n\n## Verification\n"
        }
    }

    private static func unique(_ url: URL) -> URL {
        let stem = url.deletingPathExtension()
        var candidate = url
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = stem.deletingLastPathComponent()
                .appendingPathComponent("\(stem.lastPathComponent)-\(n)")
                .appendingPathExtension(url.pathExtension)
            n += 1
        }
        return candidate
    }

    private static func yaml(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// RFC-3339 punctuation is awkward in Finder names; the sortable compact form stays
    /// in the filename while exact timestamps live in run frontmatter.
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmssZ"
        return formatter.string(from: Date())
    }

    /// `.notebook/tasks/x.md` — the agent runs in the project root, so give it that.
    package static func relativePath(_ url: URL) -> String {
        guard let range = url.path.range(of: "/\(folderName)/") else { return url.lastPathComponent }
        return folderName + "/" + url.path[range.upperBound...]
    }

    static let specText = """
        # Notebook

        Plain files. One entry = one Markdown file with YAML frontmatter. No database,
        no index to keep in sync — the folder tree is the index, so any agent or human
        with filesystem access can read and write it.

        This notebook belongs to the project folder holding it: it lives at
        `<project>/\(folderName)/`, and the agents working on it run in `<project>`.

        ## Layout

        Paths are relative to the project folder. Everything the notebook owns lives
        under `\(folderName)/` — never write these at the project root.

            \(folderName)/roadmap/<id>.md             goals and bets — the why
            \(folderName)/projects/<id>/project.md    one project — the what
            \(folderName)/projects/<id>/memory/*.md   that project's memory: decisions, context
            \(folderName)/tasks/<id>.md               shippable units of work — the how
            \(folderName)/runs/<timestamp>-<id>.md    one agent-team session — the handoff

        Memory sits inside its project on purpose: it is archived, moved and handed off
        with the project, and one file per fact means several agents can write memory at
        once without touching the same file.

        ## Frontmatter

            ---
            id: <slug>          stable, never changes — the filename may, this may not
            kind: roadmap | project | task | memory | run
            title: "<a few words>"   what it is, short enough to scan in a list — not
                                a sentence; the brief is the body's first paragraph
            status: todo | designing | active | blocked | done   (state pages only)
            depends_on: []      ids that must land first (state pages only)
            designer: <name>    tasks only — this task is design work, and this is who does
                                it. Product writes design as its own task; the engineering
                                tasks on that screen name it in depends_on, and the user
                                approving its demo is what finishes it. Empty on everything
                                else; never inferred from the title or the repo.
            repos: []           projects only — folders the work lands in, relative to the
                                project folder: [.] for the folder itself, [web, api] for two
            roadmap: <id>       projects only
            project: <id>       tasks, memory and project-scoped runs
            subject: <id>       memory and runs — the entry this record explains
            memory_type: decision | fact | constraint | assumption | note
            source: user | agent | code | external
            supersedes: []      memory ids made stale by this memory
            result: succeeded | partial | blocked | failed | cancelled   (runs only)
            agent: ""           runs only
            started: RFC-3339   runs only
            ended: RFC-3339     runs only
            owner: ""           free text — the format fixes no roles
            created: YYYY-MM-DD
            updated: YYYY-MM-DD
            external: {}        mirrors elsewhere, e.g. notion: <page-id>
            ---

        Unknown keys are preserved, never dropped. Add what a project needs.

        ## Body

        CommonMark. The first body paragraph is a one-to-three-sentence brief for a human;
        details follow under `##` headings. Omit empty sections. Tasks use `- [ ]`
        checkboxes for acceptance criteria. Cross-link entries with `[[id]]`.

        State pages (roadmap, project and task) are mutable current truth. Do not append
        dated work logs to them. Roadmaps normally use Goal, Success, Context,
        Requirements, Projects and Not doing; projects use Outcome, Done when, Context,
        Approach, Tasks and Decisions; tasks use Done when, Context and Constraints.

        ## Dependencies

        `depends_on` holds ids and crosses kinds freely: a task may depend on another
        task, a project on another project. Nothing enforces acyclicity — that is the
        author's problem.

        ## Repos

        A project's `repos` are the folders its work lands in: one for an app that is its
        own folder, several when a web app and the service behind it are separate. Fill it
        in — it is what says which code a project touches before anyone opens it, and the
        board starts each folder the way the folder itself says to (a compose file, an npm
        `dev` script, Cargo, go, a Makefile `dev` target).

        A repo holding more than one app is a monorepo, not one blob to start with a single
        command: put each independently-runnable app under its own folder in `apps/` (or
        `services/`), each with its own start command, so a web frontend and the API behind
        it come up and get reviewed separately. A compose file naming its services works too —
        either way, each app is found and started on its own, not lumped into whatever one
        command the repo root happens to have.

        ## Memory

        One durable fact, decision, constraint or assumption per file, named
        `YYYY-MM-DD-<slug>.md`. Append; do not rewrite history. Point `subject` at the
        entry it explains. Supersede stale memory with a new entry whose `supersedes`
        names the old id. Runs are history, not canonical truth: promote anything the next
        agent must rely on into durable memory.

        ## Runs

        Ordinary sessions append one handoff record with an RFC-3339 timestamp in the
        filename and frontmatter, then a brief and Handoff, Completed, Verification,
        Changed and Learned sections as applicable. A session assigned tasks keeps one
        `<session-id>-work-<work-id>.md` report per attempt at a task, `kind: run`, where
        the work id is the task id with `-2`, `-3` for a later attempt. Its flat frontmatter
        names the `session`, `task`, `work_id`, `title`, `status`, the `paths` it changed,
        a one-line `report`, `started_at` and `finished_at`; its body is `## Result`,
        `## Verification` and `## Review` — a JSON block the review page is drawn from: a
        one-sentence summary, a confidence, the checks run, the change before and after,
        places worth reading, questions and concerns — and `## Change request` quotes what
        the user sent back. A screen's before and after are the app served twice, at
        two addresses, each with the command that serves it again. Work
        states running/blocked/done/failed are separate from task states. These records
        stay out of notebook navigation and appear on the session's result and in Review.
        Keep raw transcripts outside the notebook. Never store secrets, environment
        values or machine-local transcript paths.

        ## Third-party notebooks (Notion et al.)

        The layout maps 1:1 onto a Notion workspace, so an exporter stays a pure
        function over these files:

        | here                                   | Notion             |
        |----------------------------------------|--------------------|
        | folder (`roadmap/`, `projects/`, `tasks/`, `runs/`) | database |
        | `.md` file                             | page in that database |
        | frontmatter key                        | page property      |
        | `depends_on`, `roadmap`, `project`, `subject` | relation property |
        | body                                   | page content blocks |
        | `external.notion`                      | page id, so sync is idempotent |

        What keeps that true, and must stay true: ids are stable and slug-shaped, dates
        are ISO-8601, `kind`/`status` are closed enums (Notion selects), relations are
        YAML arrays of ids, and bodies are portable CommonMark — no raw HTML, no
        machine-local paths.
        """
}
