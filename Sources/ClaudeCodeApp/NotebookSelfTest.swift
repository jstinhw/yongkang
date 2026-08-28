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
        let sid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        precondition(AgentCommand.line(directory: "/a", agent: .claude, prompt: "hi", sessionID: sid)
                     == "cd '/a' && exec claude --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'hi'")
        precondition(AgentCommand.line(directory: "/a", agent: .claude, prompt: nil, sessionID: sid)
                     == "cd '/a' && exec claude --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        precondition(AgentCommand.line(directory: "/a", agent: .codex, prompt: "hi", sessionID: sid)
                     == "cd '/a' && exec codex 'hi'",
                     "codex never understands --session-id, so passing one changes nothing")

        // Subagent transcripts live under a project's slugged folder — the slug, the pure
        // finished-detection, and an end-to-end read against fixture files.
        precondition(ClaudeTranscripts.sessionFolder(sessionID: sid, projectDirectory: URL(fileURLWithPath: "/a/b c"),
                                                      claudeHome: URL(fileURLWithPath: "/home/.claude")).path
                     == "/home/.claude/projects/-a-b c/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        precondition(ClaudeTranscripts.isFinished("toolu_1", in: "{\"tool_use_id\":\"toolu_1\"}"))
        precondition(ClaudeTranscripts.isFinished("toolu_1", in: "{\"tool_use_id\": \"toolu_1\"}"))
        precondition(!ClaudeTranscripts.isFinished("toolu_1", in: "{\"id\":\"toolu_1\"}"),
                     "a tool_use block must not read as its own result")

        let claudeHome = tmp.appendingPathComponent(".claude")
        let sessionID = UUID()
        let sessionFolder = ClaudeTranscripts.sessionFolder(sessionID: sessionID, projectDirectory: tmp,
                                                             claudeHome: claudeHome)
        let subagentsDir = sessionFolder.appendingPathComponent("subagents")
        try! fm.createDirectory(at: subagentsDir, withIntermediateDirectories: true)
        try! #"{"agentType":"claude-code-guide","description":"Research X","toolUseId":"toolu_done"}"#
            .write(to: subagentsDir.appendingPathComponent("agent-done1.meta.json"), atomically: true, encoding: .utf8)
        try! #"{"agentType":"Explore","description":"Find Y","toolUseId":"toolu_running"}"#
            .write(to: subagentsDir.appendingPathComponent("agent-running1.meta.json"), atomically: true, encoding: .utf8)
        try! #"{"type":"tool_result","tool_use_id":"toolu_done"}"#
            .write(to: sessionFolder.appendingPathExtension("jsonl"), atomically: true, encoding: .utf8)

        let subagents = ClaudeTranscripts.subagents(sessionID: sessionID, projectDirectory: tmp, claudeHome: claudeHome)
        precondition(subagents.map(\.description) == ["Find Y", "Research X"], "sorted by description")
        precondition(subagents.first { $0.id == "done1" }?.running == false,
                     "a result in the parent transcript means done")
        precondition(subagents.first { $0.id == "running1" }?.running == true, "no result yet means still running")
        precondition(subagents.first { $0.id == "done1" }?.agentType == "claude-code-guide")
        precondition(subagents.first { $0.id == "done1" }?.transcriptURL
                     == subagentsDir.appendingPathComponent("agent-done1.jsonl"))
        precondition(ClaudeTranscripts.subagents(sessionID: UUID(), projectDirectory: tmp, claudeHome: claudeHome).isEmpty,
                     "a session with no subagents folder reads as empty, not a crash")

        // The viewer's own read: a task, a tool call (thinking dropped along the way), its
        // result, and a reply, out of the same shape a subagent's own transcript is in.
        let subagentLog = subagentsDir.appendingPathComponent("agent-done1.jsonl")
        try! [
            #"{"type":"user","message":{"role":"user","content":"Do the thing"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"},{"type":"tool_use","name":"WebSearch","input":{"query":"claude code"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"some results here"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Here is the answer"}]}}"#,
        ].joined(separator: "\n").write(to: subagentLog, atomically: true, encoding: .utf8)
        let parsed = ClaudeTranscripts.transcript(at: subagentLog)
        precondition(parsed.map(\.label) == ["Task", "Tool", "Result", "Reply"], "thinking blocks are dropped")
        precondition(parsed.map(\.text) == ["Do the thing", "WebSearch(query: claude code)",
                                            "some results here", "Here is the answer"])
        precondition(ClaudeTranscripts.transcript(at: subagentsDir.appendingPathComponent("missing.jsonl")).isEmpty,
                     "a transcript that is not there yet reads as empty, not a crash")

        // A blocker is pulled into the batch rather than raised as a question.
        func node(_ id: String, _ status: String, _ waits: [String]) -> NotebookCard {
            NotebookCard(id: id, url: URL(fileURLWithPath: "/\(id).md"), kind: .task,
                         title: id, status: status, project: nil, dependsOn: waits)
        }
        let graph = [node("a", "todo", ["b"]), node("b", "todo", ["c"]), node("c", "todo", []),
                     node("d", "todo", ["done-one"]), node("done-one", "done", ["c"]),
                     node("x", "todo", ["y"]), node("y", "todo", ["x"])]
        precondition(NotebookIndex.withBlockers([graph[0]], in: graph).map(\.id) == ["c", "b", "a"],
                     "blockers come along transitively, and ahead of what they block")
        precondition(NotebookIndex.withBlockers([graph[3]], in: graph).map(\.id) == ["d"],
                     "a finished blocker is not dragged back in, nor anything behind it")
        precondition(Set(NotebookIndex.withBlockers([graph[5]], in: graph).map(\.id)) == ["x", "y"],
                     "a dependency cycle terminates instead of hanging")
        precondition(NotebookIndex.withBlockers([], in: graph).isEmpty)

        // A task already claimed by another lead is not handed to a second one, whether it
        // was picked directly or would otherwise be pulled in as a blocker.
        precondition(NotebookIndex.withBlockers([graph[0]], in: graph, excluding: ["a"]).isEmpty,
                     "an already-assigned pick is dropped, not reassigned")
        precondition(NotebookIndex.withBlockers([graph[0]], in: graph, excluding: ["b"]).map(\.id) == ["a"],
                     "an already-assigned blocker is not pulled in twice")
        precondition(NotebookIndex.withBlockers([graph[4]], in: graph).isEmpty,
                     "a task already done cannot be picked again, nor does it drag in its own blockers")

        var wip = Project(directory: tmp)
        wip.sessions = [CodeSession(title: "Engineering Lead", icon: "person.2", line: "", taskIDs: ["a", "b"]),
                        CodeSession(title: "Engineering Lead 2", icon: "person.2", line: "", taskIDs: ["c"])]
        precondition(wip.assignedTaskIDs == ["a", "b", "c"],
                     "a project's WIP set is the union of its open sessions' tasks")

        // Lanes are levels: everything in one can start once the lanes left of it are done.
        precondition(NotebookIndex.waves(graph).map { $0.map(\.id) }
                     == [["c"], ["b", "done-one"], ["a", "d"], ["x", "y"]],
                     "a chain steps one lane at a time, and a cycle lands in the last lane")
        precondition(NotebookIndex.waves([]).isEmpty)

        // A repo says how it starts, and compose wins over the app it brings up with it.
        let repo = tmp.appendingPathComponent("web")
        try! fm.createDirectory(at: repo, withIntermediateDirectories: true)
        precondition(Service.command(in: repo) == nil, "an empty folder has nothing to run")
        try! #"{"scripts": {"build": "tsc", "dev": "next dev"}, "dependencies": {"start": "1"}}"#
            .write(to: repo.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        precondition(Service.command(in: repo) == "npm run dev",
                     "the script has to come out of scripts, not any key that reads like one")
        try! "services:\n".write(to: repo.appendingPathComponent("compose.yaml"),
                                 atomically: true, encoding: .utf8)
        precondition(Service.command(in: repo) == "docker compose up",
                     "compose starts the database the app needs, so it wins")
        precondition(Service.directory("~/x", in: tmp).path == NSString(string: "~/x").expandingTildeInPath)
        precondition(Service.directory("web", in: tmp).path == repo.path)
        precondition(Service.isFrontend(repo), "a package.json is the preview's frontend signal")
        precondition(!Service.isFrontend(tmp.appendingPathComponent("api")),
                     "a repo with no package.json is not treated as a frontend app")

        let hasRepos = NotebookCard(id: "p", url: tmp, kind: .project, title: "P", status: "todo",
                                    project: nil, dependsOn: [], repos: ["web", "api"])
        let plan = Service.plan(for: hasRepos, in: tmp)
        precondition(plan.map(\.repo) == ["web", "api"])
        precondition(plan[0].services.count == 1 && plan[1].services.count == 1,
                     "no monorepo split and no named compose services is one service each")
        precondition(plan[0].services.first?.command == "docker compose up" && plan[1].services.first?.command == nil,
                     "a repo that is not there yet is reported, not dropped")
        let noRepos = NotebookCard(id: "p", url: tmp, kind: .project, title: "P", status: "todo",
                                   project: nil, dependsOn: [])
        precondition(Service.plan(for: noRepos, in: tmp).map(\.directory.path) == [tmp.path],
                     "a project without repos is its own folder")

        // Several notebook projects with no repos: of their own all fall back to the same
        // project root — that must collapse to one preview row, not one per project.
        let sameFolder = [noRepos, noRepos, noRepos].flatMap { Service.plan(for: $0, in: tmp) }
        precondition(sameFolder.count == 3, "the bug reproduces: three project cards, three plan entries")
        precondition(Service.dedupedByDirectory(sameFolder).count == 1,
                     "three project cards pointing at the same folder is one preview, not three")
        let twoRepos = NotebookCard(id: "p2", url: tmp, kind: .project, title: "P2", status: "todo",
                                    project: nil, dependsOn: [], repos: ["web", "api"])
        let mixed = Service.dedupedByDirectory(sameFolder + Service.plan(for: twoRepos, in: tmp))
        precondition(mixed.map(\.repo) == [tmp.lastPathComponent, "web", "api"],
                     "a distinct repo is kept, only the duplicate root collapses")

        // A monorepo's apps/ folder names each service on its own, independently runnable.
        let mono = tmp.appendingPathComponent("mono")
        try! fm.createDirectory(at: mono.appendingPathComponent("apps/api"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: mono.appendingPathComponent("apps/web"), withIntermediateDirectories: true)
        try! "module x\n".write(to: mono.appendingPathComponent("apps/api/go.mod"), atomically: true, encoding: .utf8)
        try! #"{"scripts": {"dev": "next dev"}}"#
            .write(to: mono.appendingPathComponent("apps/web/package.json"), atomically: true, encoding: .utf8)
        let monoServices = Service.services(in: mono)
        precondition(monoServices.map(\.name) == ["api", "web"], "apps/ names each service, sorted")
        precondition(monoServices.map(\.command) == ["go run .", "npm run dev"])

        // A compose file names its own services too, one `docker compose up <name>` each.
        let composed = tmp.appendingPathComponent("composed")
        try! fm.createDirectory(at: composed, withIntermediateDirectories: true)
        try! "services:\n  web:\n    build: .\n  worker:\n    build: ./worker\n"
            .write(to: composed.appendingPathComponent("docker-compose.yml"), atomically: true, encoding: .utf8)
        let composedServices = Service.services(in: composed)
        precondition(composedServices.map(\.name) == ["web", "worker"], "compose names its own services")
        precondition(composedServices.map(\.command) == ["docker compose up web", "docker compose up worker"])

        // apps/ is the more specific signal — it wins even when a root compose file is also there.
        try! "services:\n  db:\n    image: postgres\n"
            .write(to: mono.appendingPathComponent("docker-compose.yml"), atomically: true, encoding: .utf8)
        precondition(Service.services(in: mono).map(\.name) == ["api", "web"],
                     "a monorepo split wins over a root compose file")
        precondition(AgentCommand.line(directory: "/a b", run: "npm run dev")
                     == "cd '/a b' && npm run dev")

        // Clicking a project scopes the board to it, and takes the old scope's picks along.
        let launch = cards.first { $0.id == "launch-beta" }!
        let other = NotebookCard(id: "ship-ga", url: root, kind: .project, title: "GA",
                                 status: "todo", project: nil, dependsOn: [])
        let board = cards + [other]
        let scoped = NotebookBoard.picking(launch, in: board, from: ["bare"])
        precondition(scoped == ["bare", "launch-beta"], "a roadmap pick survives scoping")
        let withTask = scoped.union(["tricky"])
        precondition(NotebookBoard.picking(other, in: board, from: withTask) == ["bare", "ship-ga"],
                     "swapping projects drops the picks that just left the task column")
        precondition(NotebookBoard.picking(launch, in: board, from: withTask) == ["bare"],
                     "clicking the scope again unscopes the board")
        precondition(NotebookBoard.picking(tricky, in: board, from: withTask) == ["bare", "launch-beta"],
                     "a task click toggles only itself")

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

        // A follow-up batch for a lead already running carries the same task detail, without
        // re-briefing it as if it were a fresh assignment.
        let follow = NotebookFormat.additionalTasksPrompt(tasks: picked)
        for task in picked {
            precondition(follow.contains(task.id) && follow.contains(task.title))
        }
        precondition(follow.contains("waits on: wire-auth"), "dependencies have to survive a follow-up too")
        precondition(!follow.contains("You are the engineering lead"),
                     "a follow-up talks to the session that is already running, not a new one")

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
