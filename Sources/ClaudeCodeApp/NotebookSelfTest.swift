import Foundation

/// `swift run ClaudeCodeApp --selftest` — the one check that fails if the on-disk
/// notebook format drifts. preconditions, not asserts, so it also works in release.
enum NotebookSelfTest {
    static func run() {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notebook-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        precondition(NotebookFormat.slug("Ship  the *Beta*! v2") == "ship-the-beta-v2")
        precondition(NotebookFormat.slug("///") == "")

        let root = NotebookFormat.root(in: tmp)
        precondition(root.lastPathComponent == ".notebook")
        precondition(NotebookLoader.load(root: root).isEmpty, "a project with no .notebook reads as empty")
        precondition(!fm.fileExists(atPath: tmp.path), "and nothing is written to the project folder")

        let project = try! NotebookFormat.create(.project, title: "Launch Beta", in: root, project: nil)
        precondition(fm.fileExists(atPath: root.appendingPathComponent("NOTEBOOK.md").path),
                     "the first entry scaffolds the notebook")
        precondition(project.path.hasSuffix("projects/launch-beta/project.md"))
        precondition(try! String(contentsOf: project, encoding: .utf8).contains("id: launch-beta"))

        let memory = try! NotebookFormat.create(.memory, title: "Chose SQLite", in: root, project: "launch-beta")
        precondition(memory.path.contains("projects/launch-beta/memory/"))
        precondition(memory.lastPathComponent.hasSuffix("-chose-sqlite.md"))
        var threw = false
        do { _ = try NotebookFormat.create(.memory, title: "Orphan", in: root, project: nil) } catch { threw = true }
        precondition(threw, "memory needs a project")

        let first = try! NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        let second = try! NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        precondition(first != second, "same title must not clobber an existing task")
        let task = try! String(contentsOf: first, encoding: .utf8)
        for field in ["id: wire-auth", "kind: task", "title: \"Wire auth\"", "status: todo",
                      "project: launch-beta", "depends_on: []", "external: {}"] {
            precondition(task.contains(field), "task frontmatter missing \(field)")
        }

        let tree = NotebookLoader.load(root: root)
        precondition(tree.map(\.title) == ["roadmap", "projects", "tasks"])
        let projectRow = tree.first { $0.title == "projects" }!.children!.first!
        precondition(projectRow.title == "launch-beta")
        precondition(projectRow.url.lastPathComponent == "project.md", "a project row opens its own page")
        precondition(projectRow.id == NotebookEntry.id(for: project.deletingLastPathComponent()),
                     "add(.project) selects the folder row by this id")
        precondition(projectRow.children!.map(\.title) == ["memory"])
        // Icons come from the path, and memory sits under projects/ — it must win.
        precondition(projectRow.icon == NotebookLoader.icon(forFolder: "projects"))
        precondition(projectRow.children![0].children![0].icon == "brain")
        precondition(projectRow.children![0].children!.count == 1)
        precondition(NotebookLoader.find(NotebookEntry.id(for: first), in: tree)?.title == "wire-auth")
        // project.md + one memory + two tasks; bare folders are not pages.
        precondition(NotebookLoader.pageCount(tree) == 4)

        // The onboarding prompt reaches the agent as a shell argument, and it is full of
        // apostrophes, newlines, backticks and pipes. Round-trip it through a real shell.
        // Frontmatter as agents actually write it: a title with a colon and commas, an
        // inline dependency list, and a key the app has never heard of.
        try! """
        ---
        id: tricky
        kind: task
        title: "Ship it: fast, cheap"
        status: blocked
        depends_on: [wire-auth, "gone-missing"]
        project: launch-beta
        target: ""
        external: {}
        ---

        ## Done when
        """.write(to: root.appendingPathComponent("tasks/tricky.md"), atomically: true, encoding: .utf8)
        // No frontmatter at all — the board still has to place it.
        try! "just notes\n".write(to: root.appendingPathComponent("roadmap/bare.md"),
                                  atomically: true, encoding: .utf8)

        let cards = NotebookIndex.load(root: root)
        let tricky = cards.first { $0.id == "tricky" }!
        precondition(tricky.title == "Ship it: fast, cheap")
        precondition(tricky.status == "blocked")
        precondition(tricky.dependsOn == ["wire-auth", "gone-missing"])
        precondition(tricky.project == "launch-beta")
        precondition(tricky.kind == .task)
        let bare = cards.first { $0.url.lastPathComponent == "bare.md" }!
        precondition(bare.id == "bare" && bare.title == "bare" && bare.kind == .roadmap,
                     "a file without frontmatter falls back to its filename and folder")
        precondition(cards.first { $0.id == "launch-beta" }?.kind == .project)
        precondition(cards.contains { $0.kind == .memory && $0.project == "launch-beta" })
        precondition(cards.count == NotebookLoader.pageCount(NotebookLoader.load(root: root)))

        // The agent copies paths straight out of the layout block. Every one has to be
        // anchored to .notebook/, or it creates roadmap/ and tasks/ at the project root.
        for folder in NotebookFormat.folders {
            precondition(NotebookFormat.specText.contains(".notebook/\(folder)/"),
                         "\(folder) is not anchored to .notebook/ in the spec")
            precondition(!NotebookFormat.specText.contains("\n    \(folder)/"),
                         "\(folder) still appears as a bare project-root path in the spec")
        }

        let typed = "It's a CLI that syncs \"stuff\"\nfast; `now`"
        let prompt = NotebookFormat.onboardingPrompt(description: typed)
        precondition(prompt.contains(typed), "what the user typed reaches the agent")
        precondition(prompt.contains("author's problem"), "the spec's apostrophes are what break quoting")
        precondition(echo(AgentCommand.quoted(prompt)) == prompt, "prompt mangled by the shell")
        precondition(echo(AgentCommand.quoted("/a b'c")) == "/a b'c")
        precondition(AgentCommand.line(directory: "/a b", agent: .claude, prompt: nil)
                     == "cd '/a b' && exec claude")
        precondition(AgentCommand.line(directory: "/a", agent: .codex, prompt: "hi there")
                     == "cd '/a' && exec codex 'hi there'")

        // Picked tasks reach the lead as a shell argument, titles and all.
        let picked = cards.filter { $0.kind == .task }
        precondition(picked.count >= 2)
        let brief = NotebookFormat.engineeringPrompt(tasks: picked)
        for task in picked {
            precondition(brief.contains(task.id) && brief.contains(task.title))
            precondition(brief.contains(".notebook/tasks/\(task.url.deletingPathExtension().lastPathComponent).md"),
                         "the lead needs a path it can open from the project root")
        }
        precondition(brief.contains("waits on: wire-auth"), "dependencies have to survive")
        precondition(echo(AgentCommand.quoted(brief)) == brief, "task brief mangled by the shell")

        // The open-project list lives in defaults, where anything could be sitting.
        let paths = ["/a/b", "/quote\"path", "/a b/c", tmp.path]
        precondition(OpenProjects.decode(OpenProjects.encode(paths)) == paths)
        precondition(OpenProjects.decode("").isEmpty)
        precondition(OpenProjects.decode("{\"not\": \"a list\"}").isEmpty)

        print("notebook selftest ok")
    }

    /// What zsh actually passes to the agent for a given quoted argument.
    private static func echo(_ quotedArgument: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf %s \(quotedArgument)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try! process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
