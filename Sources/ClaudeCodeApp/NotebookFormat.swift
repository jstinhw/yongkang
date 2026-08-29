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
        if kind == .project { fields.append(("repos", "[]")) }
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
        This project has no notebook yet. We are going to start one.

        Here is what I want to build, in my words:

        \(description)

        First, ask me what you actually need to know — never as an open question. Come
        with the answers already worked out: two to four concrete options, numbered,
        your recommendation first and marked as such, so I can answer with a single
        character. If none of them fit I will tell you.

        Ask about what is missing or ambiguous in what I just told you: who it is for,
        the features, the constraints, what is out of scope, and what has to happen
        before what. One question at a time, a handful of them rather than an
        interrogation, and write no files while we are talking.

        Then write the notebook. Do not show me a plan first and do not wait for my
        approval — I would rather read a real notebook than approve an imaginary one. I
        will read it on the board and tell you what to change.

        It all goes into `\(folderName)/` in this folder — every file this produces goes in
        there and nowhere else. Do not create roadmap/, projects/ or tasks/ at the
        project root, and leave everything outside `\(folderName)/` untouched.

        Start with `\(folderName)/\(specFile)`, the format below, verbatim. Then the files it
        describes, following its frontmatter exactly: my goals as roadmap entries, the
        projects that get us there with `depends_on` where one blocks another and `repos`
        naming the folders each one's work lands in, and the tasks that ship each project,
        each carrying its `project:` and its own `depends_on`. Order matters more than volume — the dependencies are what I am
        going to read.

        Where something is still vague once we have talked, make the call rather than
        asking again, and record it: one memory entry in the project it affects, saying
        what you assumed and why. Leave `owner` and any date empty rather than
        inventing one.

        When the files are written, stop and tell me in a few lines what you created and
        which calls you made, then wait for my corrections.

        Here is the format to write verbatim to `\(folderName)/\(specFile)`, and then follow:

        \(specText)
        """
    }

    private static func taskList(_ tasks: [NotebookCard]) -> String {
        tasks.map { task in
            var line = "- \(task.id) — \(task.title)\n  file: \(relativePath(task.url))"
            if let project = task.project { line += "\n  project: \(project)" }
            if !task.dependsOn.isEmpty { line += "\n  waits on: \(task.dependsOn.joined(separator: ", "))" }
            return line
        }.joined(separator: "\n")
    }

    /// Hands a batch of picked tasks to one lead session. The engineers are that
    /// session's own subagents: separate PTYs would have no way to report back to it.
    static func engineeringPrompt(tasks: [NotebookCard]) -> String {
        """
        You are the engineering lead on this project. I picked these tasks out of the
        notebook — ship them.

        \(taskList(tasks))

        Read each task file first: the body says what done means and the frontmatter says
        what it waits on.

        The list is the whole job, already in dependency order and already carrying every
        unfinished blocker of what I picked. Ship all of it. A blocker being unfinished is
        why it is on the list, never a reason to hand the batch back to me — a task I
        asked for is not shipped until the things it waits on are. If you turn up another
        blocker that is not listed, pull it in and do it first. Do not ask me to scope
        this, and do not ask me to do any of it myself.

        Delegate the implementation — do not write it yourself. Give each task to its own
        subagent, with the task file and what done means, and run tasks that do not block
        each other in parallel. Blockers get their own subagents like anything else: the
        team is however many engineers the batch needs.

        When a subagent reports back, review before you accept: read the diff and check it
        does what the task says and nothing more. If it falls short, hand it back with what
        is missing rather than fixing it yourself.

        Keep the notebook true as you go — `status: active` when you hand a task out,
        `status: done` only once you have accepted the work, and one memory entry in the
        affected project for anything you learned that the next person would need. If the
        work lands in a folder the project's `repos:` does not list, add it: that key is
        what lets the project be started and reviewed.

        Some tasks need something that lives in my accounts — a Vercel or GitHub login, a
        dashboard-provisioned database, a secret, a paid plan. Those are the only things
        you may come to me for, and never at the start. Build everything that can be built
        without them first: scaffold the app, stand up a local substitute where the cloud
        piece is not there yet — a local database, a dev server, a stub behind the same
        env var — and take every task behind it as far as it goes locally. Leave the
        account task itself `todo` and say why; do not mark it done off a local stand-in.

        Come to me once, at the end, when everything left is waiting on me and nothing
        else can move. One message, every account thing you need in it: what is blocked,
        and numbered steps for exactly what I click or run. Never a menu of options for me
        to pick scope from — deciding what to build is your job, not mine.

        When every task has passed your review, open the pull request: a branch, a commit
        per task whose message says what it does, then `gh pr create` with a body listing
        the tasks by notebook id. Then stop and tell me it is up for review. Do not merge
        it — that call is mine. If `gh` is missing or not logged in, say so and leave the
        branch pushed rather than guessing at another way.
        """
    }

    /// A second (or third) batch for a lead session that is already running — talked to
    /// like the ongoing conversation it is, not re-briefed as if it were new.
    static func additionalTasksPrompt(tasks: [NotebookCard]) -> String {
        """
        More tasks for you, on top of what you already have — same rules as before: read
        each one first, delegate to its own subagent, pull in any blocker that turns up
        even if it is not listed here, review before you accept, and fold these into the
        same PR when you open it rather than a second one.

        \(taskList(tasks))
        """
    }

    /// `.notebook/tasks/x.md` — the agent runs in the project root, so give it that.
    private static func relativePath(_ url: URL) -> String {
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
        repos: []           projects only — folders the work lands in, relative to the
                            project folder: [.] for the folder itself, [web, api] for two
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
