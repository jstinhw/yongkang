import Foundation

enum EntryKind: String, CaseIterable {
    case roadmap, project, task, memory

    var displayName: String { rawValue.capitalized }
}

enum NotebookError: LocalizedError {
    case emptyTitle
    case missingProject

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Give the entry a title."
        case .missingProject: return "Select a project first — memory lives inside a project."
        }
    }
}

/// On-disk shape of a notebook. Everything here is plain Markdown so the coding
/// agents running in the sidebar read and write it with no extra plumbing.
enum NotebookFormat {
    static let folderName = ".notebook"
    static let specFile = "NOTEBOOK.md"
    static let folders = ["roadmap", "projects", "tasks"]

    /// Where a project keeps its notebook. Nothing is written until the first entry:
    /// a project with no `.notebook` stays untouched and simply reads as empty.
    static func root(in project: URL) -> URL { project.appendingPathComponent(folderName) }

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

    static func create(_ kind: EntryKind, title: String, in root: URL, project: String?) throws -> URL {
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
            return try write(file, id: file.deletingPathExtension().lastPathComponent,
                             kind: kind, title: title, project: project, day: day)

        case .project:
            var dir = root.appendingPathComponent("projects/\(base)")
            var n = 2
            while fm.fileExists(atPath: dir.path) {
                dir = root.appendingPathComponent("projects/\(base)-\(n)")
                n += 1
            }
            try fm.createDirectory(at: dir.appendingPathComponent("memory"), withIntermediateDirectories: true)
            return try write(dir.appendingPathComponent("project.md"), id: dir.lastPathComponent,
                             kind: kind, title: title, project: nil, day: day)

        case .memory:
            guard let project, !project.isEmpty else { throw NotebookError.missingProject }
            let dir = root.appendingPathComponent("projects/\(project)/memory")
            let file = unique(dir.appendingPathComponent("\(day)-\(base).md"))
            return try write(file, id: file.deletingPathExtension().lastPathComponent,
                             kind: kind, title: title, project: project, day: day)
        }
    }

    static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { ch in ch.isASCII && (ch.isLetter || ch.isNumber) ? ch : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }

    // MARK: - Writing

    private static func write(_ file: URL, id: String, kind: EntryKind,
                              title: String, project: String?, day: String) throws -> URL {
        var fields: [(String, String)] = [
            ("id", id),
            ("kind", kind.rawValue),
            ("title", yaml(title)),
        ]
        if kind != .memory { fields.append(("status", "todo")) }
        if kind == .task || kind == .memory { fields.append(("project", project ?? "")) }
        if kind != .memory {
            fields.append(("depends_on", "[]"))
            fields.append(("owner", "\"\""))
        }
        fields.append(contentsOf: [("created", day), ("updated", day), ("external", "{}")])

        let front = fields.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        let text = "---\n\(front)\n---\n\n\(body(for: kind))"
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
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
        let escaped = value
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

    /// Opens the session an empty project starts with, seeded by what the user typed.
    /// It carries the spec inline rather than pointing at NOTEBOOK.md, because the
    /// point of an empty project is that nothing has been written to it yet — the
    /// agent writes the first file.
    static func onboardingPrompt(description: String) -> String {
        """
        This project has no notebook yet. We are going to start one together.

        Here is what I want to build, in my words:

        \(description)

        Now talk it through with me — do not write any files during this part. Ask about
        what is missing or ambiguous in what I just told you: the goal, who it is for,
        the features, the constraints, what is explicitly out of scope, and what has to
        happen before what. One focused question at a time, and keep going until you
        could explain this project back to me without hand-waving.

        Then show me the plan before you create anything: the roadmap entries, the
        projects that get us there, which projects depend on which, and the tasks that
        ship each one. Let me correct it.

        Once I agree, write it all into `\(folderName)/` in this folder — every file this
        produces goes in there and nowhere else. Do not create roadmap/, projects/ or
        tasks/ at the project root, and leave everything outside `\(folderName)/` untouched.

        Start with `\(folderName)/\(specFile)`, the format below, verbatim. Then create the
        roadmap, project, memory and task files it describes, filled in with what I told
        you and following its frontmatter exactly.

        Use only what I actually tell you. Where something is unknown, ask me or leave
        the field empty — never invent goals, dates, owners or dependencies.

        Here is the format to write verbatim to `\(folderName)/\(specFile)`, and then follow:

        \(specText)
        """
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

    Memory sits inside its project on purpose: it is archived, moved and handed off
    with the project, and one file per fact means several agents can write memory at
    once without touching the same file.

    ## Frontmatter

        ---
        id: <slug>          stable, never changes — the filename may, this may not
        kind: roadmap | project | task | memory
        title: "One line"
        status: todo | active | blocked | done     (not on memory)
        depends_on: []      ids that must land first (not on memory)
        project: <id>       tasks and memory only
        owner: ""           free text — the format fixes no roles
        created: YYYY-MM-DD
        updated: YYYY-MM-DD
        external: {}        mirrors elsewhere, e.g. notion: <page-id>
        ---

    Unknown keys are preserved, never dropped. Add what a project needs.

    ## Body

    CommonMark. Tasks use `- [ ]` checkboxes for subtasks. Cross-link entries with
    `[[id]]`.

    ## Dependencies

    `depends_on` holds ids and crosses kinds freely: a task may depend on another
    task, a project on another project. Nothing enforces acyclicity — that is the
    author's problem.

    ## Memory

    One fact or decision per file, named `YYYY-MM-DD-<slug>.md`. Append; do not
    rewrite history. Supersede a stale fact with a new entry that links `[[the-old-id]]`.

    ## Third-party notebooks (Notion et al.)

    The layout maps 1:1 onto a Notion workspace, so an exporter stays a pure
    function over these files:

    | here                                   | Notion             |
    |----------------------------------------|--------------------|
    | folder (`roadmap/`, `projects/`, `tasks/`) | database        |
    | `.md` file                             | page in that database |
    | frontmatter key                        | page property      |
    | `depends_on`, `project`                | relation property  |
    | body                                   | page content blocks |
    | `external.notion`                      | page id, so sync is idempotent |

    What keeps that true, and must stay true: ids are stable and slug-shaped, dates
    are ISO-8601, `kind`/`status` are closed enums (Notion selects), relations are
    YAML arrays of ids, and bodies are portable CommonMark — no raw HTML, no
    machine-local paths.
    """
}
