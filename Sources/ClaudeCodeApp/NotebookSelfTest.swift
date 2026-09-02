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

        let project = try! NotebookFormat.create(.project, title: "Launch Beta", in: root,
                                                 project: nil, roadmap: "ship-beta")
        precondition(fm.fileExists(atPath: root.appendingPathComponent("NOTEBOOK.md").path),
                     "the first entry scaffolds the notebook")
        precondition(project.path.hasSuffix("projects/launch-beta/project.md"))
        let projectText = try! String(contentsOf: project, encoding: .utf8)
        precondition(projectText.contains("id: launch-beta"))
        precondition(projectText.contains("roadmap: ship-beta"))

        let memory = try! NotebookFormat.create(.memory, title: "Chose SQLite", in: root, project: "launch-beta")
        precondition(memory.path.contains("projects/launch-beta/memory/"))
        precondition(memory.lastPathComponent.hasSuffix("-chose-sqlite.md"))
        let memoryText = try! String(contentsOf: memory, encoding: .utf8)
        for field in ["subject: launch-beta", "memory_type: note", "source: user", "supersedes: []"] {
            precondition(memoryText.contains(field), "memory frontmatter missing \(field)")
        }
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

        let run = try! NotebookFormat.create(.run, title: "Auth partially wired", in: root,
                                             project: "launch-beta", subject: "wire-auth")
        let runText = try! String(contentsOf: run, encoding: .utf8)
        for field in ["kind: run", "project: launch-beta", "subject: wire-auth", "result: partial"] {
            precondition(runText.contains(field), "run frontmatter missing \(field)")
        }

        let tree = NotebookLoader.load(root: root)
        precondition(tree.map(\.title) == ["roadmap", "projects", "tasks"])
        precondition(NotebookLoader.find(NotebookEntry.id(for: run), in: tree) == nil,
                     "run history stays out of human notebook navigation")
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
        let doneRows = [
            NotebookCard(id: "launch-beta", url: project, kind: .project, title: "Launch Beta",
                         status: "done", project: nil, dependsOn: []),
            NotebookCard(id: "wire-auth", url: first, kind: .task, title: "Wire auth",
                         status: "done", project: "launch-beta", dependsOn: []),
        ]
        let unfinishedTree = NotebookLoader.display(tree, cards: doneRows, showDone: false)
        precondition(NotebookLoader.find(projectRow.id, in: unfinishedTree) == nil)
        precondition(NotebookLoader.find(NotebookEntry.id(for: first), in: unfinishedTree) == nil)
        precondition(NotebookLoader.find(projectRow.id,
                                         in: NotebookLoader.display(tree, cards: doneRows, showDone: true)) != nil,
                     "Show Completed restores done project and task rows")
        // project.md + one memory + two tasks; runs and bare folders are not shown.
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
        precondition(cards.first { $0.id == "launch-beta" }?.roadmap == "ship-beta")
        precondition(cards.contains { $0.kind == .memory && $0.project == "launch-beta" })
        precondition(cards.contains { $0.kind == .run && $0.subject == "wire-auth" && $0.result == "partial" })
        precondition(cards.count == NotebookLoader.pageCount(NotebookLoader.loadAll(root: root)))

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
        precondition(prompt.contains("append one run record"), "setup sessions must leave a handoff")
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
        precondition(AgentCommand.line(directory: "/a", agent: .claude, prompt: "lead", sessionID: sid,
                                       brief: true)
                     == "cd '/a' && exec claude --brief --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'lead'",
                     "engineering leads can notify the user without changing ordinary sessions")
        precondition(AgentCommand.line(directory: "/a", agent: .codex, prompt: "hi", sessionID: sid)
                     == "cd '/a' && exec codex 'hi'",
                     "codex never understands --session-id, so passing one changes nothing")
        precondition(AgentKind.claude.skillInvocation("product", arguments: "review") == "/product review")
        precondition(AgentKind.codex.skillInvocation("product", arguments: "review") == "$product review")
        precondition(AgentKind.claude.skillInvocation("product", arguments: "describe") == "/product describe")
        precondition(AgentKind.codex.skillInvocation("product", arguments: "describe") == "$product describe")
        let bundled = AgentKind.codex.skill("product", arguments: "describe",
                                             instructions: "Only write notebook files.")
        precondition(bundled.contains("Only write notebook files.")
                     && bundled.contains("<arguments>\ndescribe\n</arguments>")
                     && !bundled.contains("$product"),
                     "a packaged session must not depend on project or global skill discovery")
        if CommandLine.arguments[0].contains(".app/Contents/MacOS/") {
            precondition(BundledSkills.load("product")?.contains("name: product") == true,
                         "the packaged app must carry its Product skill")
        }

        // Subagent transcripts live under a project's slugged folder — the slug, the pure
        // finished-detection, and an end-to-end read against fixture files.
        precondition(ClaudeTranscripts.sessionFolder(sessionID: sid, projectDirectory: URL(fileURLWithPath: "/a/b c"),
                                                      claudeHome: URL(fileURLWithPath: "/home/.claude")).path
                     == "/home/.claude/projects/-a-b c/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        precondition(ClaudeTranscripts.isFinished(agentID: "agent1", label: "task-frontend",
                                                  toolUseID: "toolu_1",
                                                  in: "{\"tool_use_id\":\"toolu_1\"}"))
        precondition(ClaudeTranscripts.isFinished(agentID: "agent1", label: "task-frontend",
                                                  toolUseID: "toolu_1",
                                                  in: "{\"tool_use_id\": \"toolu_1\"}"))
        precondition(!ClaudeTranscripts.isFinished(agentID: "agent1", label: "task-frontend",
                                                   toolUseID: "toolu_1", in: "{\"id\":\"toolu_1\"}"),
                     "a tool_use block must not read as its own result")
        let asyncLaunch = #"{"tool_use_id":"toolu_async","content":"Async agent launched successfully. The agent is working in the background."}"#
        let stopped = #"{"content":"<task-id>agent1</task-id><status>completed</status>"}"#
        let resumed = #"{"name":"SendMessage","input":{"recipient":"agent1"}}"#
        precondition(!ClaudeTranscripts.isFinished(agentID: "agent1", label: "task-frontend",
                                                   toolUseID: "toolu_async", in: asyncLaunch),
                     "an async launch receipt means the agent is still running")
        precondition(ClaudeTranscripts.isFinished(agentID: "agent1", label: "task-frontend",
                                                  toolUseID: "toolu_async", in: asyncLaunch + "\n" + stopped),
                     "the matching task notification ends a background agent")
        precondition(!ClaudeTranscripts.isFinished(agentID: "agent1", label: "task-frontend",
                                                   toolUseID: "toolu_async",
                                                   in: [asyncLaunch, stopped, resumed].joined(separator: "\n")),
                     "messaging a stopped agent resumes it")

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

        // Neither CLI records which task a subagent is for, so the link is its own name —
        // however that provider slugs it, and longest id first so a prefix cannot steal it.
        let batch = ["edit-todo", "edit-todo-api", "deploy-to-vercel"]
        precondition(Subagents.taskID(in: "edit_todo_frontend_dev", from: batch) == "edit-todo")
        precondition(Subagents.taskID(in: "qa-dev: deploy-to-vercel", from: batch) == "deploy-to-vercel")
        precondition(Subagents.taskID(in: "Edit Todo API (backend)", from: batch) == "edit-todo-api",
                     "the longer id wins over the one that is its prefix")
        precondition(Subagents.taskID(in: "Compact conversation", from: batch) == nil,
                     "a subagent named after no task belongs to no task")
        let grouped = Subagents.grouped([
            SubagentStatus(id: "frontend", description: "build-ui-foundation-frontend-dev",
                           agentType: "frontend-dev", running: false, transcriptURL: tmp,
                           taskID: "build-ui-foundation"),
            SubagentStatus(id: "qa", description: "build-ui-foundation-qa-dev",
                           agentType: "qa-dev", running: true, transcriptURL: tmp,
                           taskID: "build-ui-foundation")
        ], by: ["build-ui-foundation", "waiting-on-dependency"])
        precondition(grouped.map(\.id) == ["build-ui-foundation", "waiting-on-dependency"]
                     && grouped.map(\.subagents.count) == [2, 0],
                     "a lead's subagents are grouped under every assigned task")
        precondition(Subagents.runningTaskIDs(grouped.flatMap(\.subagents)) == ["build-ui-foundation"],
                     "a running child keeps its task in WIP")
        precondition(CodeSession(title: "Engineering Lead", icon: "person.2", line: "claude",
                                 subagents: grouped.flatMap(\.subagents))
                     .activeSubagents.map(\.id) == ["qa"],
                     "a finished agent drops off the lead's lists")
        precondition(ClaudeTranscripts.subagents(sessionID: sessionID, projectDirectory: tmp,
                                                  taskIDs: ["research-x"], claudeHome: claudeHome)
                     .first { $0.id == "done1" }?.taskID == "research-x",
                     "a Claude subagent carries the task its description names")

        // Codex picks its own thread id, so its lead is found by the session id its opening
        // prompt quotes, and its subagents by the rollouts pointing back at that thread.
        let codexHome = tmp.appendingPathComponent(".codex")
        let day = codexHome.appendingPathComponent("sessions/2026/09/01")
        try! fm.createDirectory(at: day, withIntermediateDirectories: true)
        let codexSession = UUID()
        func rollout(_ name: String, _ lines: [String]) -> URL {
            let url = day.appendingPathComponent(name)
            try! lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        _ = rollout("rollout-lead.jsonl", [
            #"{"type":"session_meta","payload":{"id":"thread-lead","cwd":"\#(tmp.path)","source":"cli"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"session: \#(codexSession.uuidString.lowercased())"}]}}"#,
        ])
        _ = rollout("rollout-other.jsonl", [
            #"{"type":"session_meta","payload":{"id":"thread-other","cwd":"\#(tmp.path)","source":"cli"}}"#,
        ])
        let spawn = #"{"subagent":{"thread_spawn":{"parent_thread_id":"thread-lead","agent_path":"/root/edit_todo_frontend","agent_nickname":"Hilbert","agent_role":null}}}"#
        let child = rollout("rollout-child.jsonl", [
            #"{"type":"session_meta","payload":{"id":"thread-child","cwd":"\#(tmp.path)","source":\#(spawn)}}"#,
            #"{"type":"response_item","payload":{"type":"agent_message","content":[{"type":"input_text","text":"Message Type: NEW_TASK"},{"type":"encrypted_content","encrypted_content":"gAAA"}]}}"#,
            #"{"type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"ls"}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call_output","output":[{"type":"input_text","text":"one file"}]}}"#,
            #"{"type":"event_msg","payload":{"type":"agent_message","message":"ignored, the response_item beside it says the same"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done"}]}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        ])
        let grandchildSpawn = #"{"subagent":{"thread_spawn":{"parent_thread_id":"thread-child","agent_path":"/root/edit_todo_qa","agent_nickname":"Noether","agent_role":"qa-dev"}}}"#
        _ = rollout("rollout-grandchild.jsonl", [
            #"{"type":"session_meta","payload":{"id":"thread-grandchild","cwd":"\#(tmp.path)","source":\#(grandchildSpawn)}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        ])
        CodexTranscripts.launched = .distantPast
        let codexAgents = CodexTranscripts.subagents(sessionID: codexSession, projectDirectory: tmp,
                                                     taskIDs: ["edit-todo"], codexHome: codexHome)
        precondition(codexAgents.map(\.description) == ["edit_todo_frontend", "edit_todo_qa"],
                     "every descendant of this session's thread is affiliated with the lead")
        precondition(codexAgents.allSatisfy { $0.taskID == "edit-todo" },
                     "descendants stay linked by the task in their names")
        precondition(codexAgents.first?.agentType == "Hilbert", "no role recorded falls back to the nickname")
        precondition(codexAgents.last?.agentType == "qa-dev", "a recorded descendant role is kept")
        precondition(codexAgents.allSatisfy(\.running), "started descendants remain running until complete")
        precondition(CodexTranscripts.subagents(sessionID: UUID(), projectDirectory: tmp,
                                                codexHome: codexHome).isEmpty,
                     "a session whose thread is not on disk reads as empty, not a crash")
        try! (((try! String(contentsOf: child, encoding: .utf8))
               + "\n" + #"{"type":"event_msg","payload":{"type":"task_complete"}}"#))
            .write(to: child, atomically: true, encoding: .utf8)
        precondition(CodexTranscripts.isRunning(child) == false, "the last marker written wins")

        let codexLines = CodexTranscripts.transcript(at: child)
        precondition(codexLines.map(\.label) == ["Task", "Tool", "Result", "Reply"],
                     "reasoning and the duplicate event_msg lines are dropped")
        precondition(codexLines.map(\.text) == ["Message Type: NEW_TASK", "exec(ls)", "one file", "Done"])

        // A blocker is pulled into the batch rather than raised as a question.
        func node(_ id: String, _ status: String, _ waits: [String], project: String? = nil) -> NotebookCard {
            NotebookCard(id: id, url: URL(fileURLWithPath: "/\(id).md"), kind: .task,
                         title: id, status: status, project: project, dependsOn: waits)
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

        // A task can wait on a whole project. Pull in that project's unfinished tasks,
        // not the project card: only task files can be assigned to Engineering Lead.
        let projectBlocker = NotebookCard(id: "edit-and-order", url: URL(fileURLWithPath: "/project.md"),
                                          kind: .project, title: "Edit and order", status: "todo",
                                          project: nil, dependsOn: ["todo-crud"])
        let finishedProject = NotebookCard(id: "todo-crud", url: URL(fileURLWithPath: "/crud.md"),
                                           kind: .project, title: "CRUD", status: "done",
                                           project: nil, dependsOn: [])
        let projectGraph = [
            node("builder-ui-foundation", "todo", ["edit-and-order"], project: "builder-ui-redesign"),
            projectBlocker,
            node("edit-todo", "active", ["toggle-and-delete"], project: "edit-and-order"),
            node("sort-order", "done", ["toggle-and-delete"], project: "edit-and-order"),
            finishedProject,
            node("toggle-and-delete", "done", [], project: "todo-crud")
        ]
        let projectBatch = NotebookIndex.withBlockers([projectGraph[0]], in: projectGraph)
        precondition(projectBatch.map(\.id) == ["edit-todo", "builder-ui-foundation"],
                     "an unfinished project blocker contributes all of its unfinished tasks")
        precondition(projectBatch.last?.dependsOn == ["edit-todo"],
                     "the lead sees the concrete task prerequisite, not an unassignable project page")
        precondition(NotebookIndex.withBlockers([], in: graph).isEmpty)
        precondition(NotebookIndex.visible([graph[0], graph[4]], showDone: false).map(\.id) == ["a"])
        precondition(NotebookIndex.visible([graph[0], graph[4]], showDone: true).map(\.id) == ["a", "done-one"])

        // A project is off the board once its last task passes, without anything having
        // written `status: done` on the project file itself.
        let shipped = NotebookCard(id: "shipped", url: tmp, kind: .project, title: "Shipped",
                                   status: "active", project: nil, dependsOn: [])
        let openProject = NotebookCard(id: "wip", url: tmp, kind: .project, title: "WIP",
                                       status: "active", project: nil, dependsOn: [])
        let projectTasks = [
            NotebookCard(id: "t1", url: tmp, kind: .task, title: "One", status: "done",
                         project: "shipped", dependsOn: []),
            NotebookCard(id: "t2", url: tmp, kind: .task, title: "Two", status: "todo",
                         project: "wip", dependsOn: [])
        ]
        let rail = [shipped, openProject] + projectTasks
        precondition(NotebookIndex.isFinished(shipped, in: rail), "every task done finishes the project")
        precondition(!NotebookIndex.isFinished(openProject, in: rail), "one task left keeps it on the board")
        precondition(!NotebookIndex.isFinished(shipped, in: [shipped]),
                     "a project with no tasks yet is not finished")

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

        // A project or task page is parsed into structured content, not shown as raw
        // Markdown — real pages restate the title as `# `, put a checklist right after
        // the intro with no heading of its own, and wrap a checklist item's text onto a
        // continuation line with no bullet.
        precondition(NotebookIndex.body("no frontmatter here") == "no frontmatter here")
        let real = """
        # Scaffold the app

        Intro line one
        intro line two.

        - [x] done item
        - [ ] open item that wraps onto a
              continuation line

        ## Blocked on accounts

        Stays `todo` on purpose.

        ## Tasks

        - [[a]]
        - [[b]] — annotated, so it stays

        """
        let content = NotebookContent.sections(real)
        precondition(content.map(\.heading) == [nil, "Blocked on accounts", "Tasks"],
                     "the `# ` title restates the frontmatter and is dropped, not shown as a section")
        precondition(content[0].blocks == [
            .paragraph("Intro line one intro line two."),
            .checklist([.init(text: "done item", done: true),
                        .init(text: "open item that wraps onto a continuation line", done: false)]),
        ], "a wrapped checklist line folds into the item it continues, not a stray paragraph")
        precondition(content[1].blocks == [.paragraph("Stays `todo` on purpose.")])
        precondition(content[2].blocks == [.list(["[[a]]", "[[b]] — annotated, so it stays"])])

        let rich = NotebookContent.sections("""
        ## Steps

        1. Open settings
        2. Save the value

            select * from todos;

        ```sh
        npm test
        ```
        """)
        precondition(rich[0].blocks == [
            .numberedList(["Open settings", "Save the value"]),
            .code("select * from todos;"),
            .code("npm test"),
        ], "memory pages keep numbered procedures and code readable")

        // Cross-links: a bare `[[id]]` list item is a pure reference; one with trailing
        // prose is not, even though it still contains a link.
        precondition(NotebookContent.wikilinks(in: "See [[a]] and [[b]] too") == ["a", "b"])
        precondition(NotebookContent.isPureLinks("[[a]]"))
        precondition(!NotebookContent.isPureLinks("[[a]] — why it matters"))
        precondition(!NotebookContent.isPureLinks("no link here"))
        precondition(NotebookContent.tokens("open [[x")
                     == [.text("open "), .text("[[x")], "an unmatched [[ is kept as plain text")

        // The board holds one kind of card now — every task is a candidate for the same
        // batch — so picking is a plain toggle.
        precondition(NotebookBoard.picking(tricky, from: ["bare"]) == ["bare", "tricky"],
                     "a card click adds itself to the batch")
        precondition(NotebookBoard.picking(tricky, from: ["bare", "tricky"]) == ["bare"],
                     "clicking it again takes it out")

        // Picked tasks reach the lead as a shell argument, titles and all.
        let picked = cards.filter { $0.kind == .task }
        precondition(picked.count >= 2)
        let leadID = UUID()
        let brief = NotebookFormat.engineeringPrompt(tasks: picked, sessionID: leadID, agent: .claude)
        precondition(brief.contains(leadID.uuidString.lowercased()),
                     "a lead has to know its own session id to route a block's answer back")
        precondition(brief.contains("engineering-lead"), "task batches invoke the dispatcher skill")
        for task in picked {
            precondition(brief.contains(task.id) && brief.contains(task.title))
            precondition(brief.contains(".notebook/tasks/\(task.url.deletingPathExtension().lastPathComponent).md"),
                         "the lead needs a path it can open from the project root")
        }
        precondition(brief.contains("waits on: wire-auth"), "dependencies have to survive")
        precondition(echo(AgentCommand.quoted(brief)) == brief, "task brief mangled by the shell")

        // A follow-up batch reinvokes the same dispatcher with the same task detail.
        let follow = NotebookFormat.additionalTasksPrompt(tasks: picked, sessionID: leadID, agent: .claude)
        for task in picked {
            precondition(follow.contains(task.id) && follow.contains(task.title))
        }
        precondition(follow.contains("waits on: wire-auth"), "dependencies have to survive a follow-up too")
        precondition(follow.contains("engineering-lead"), "follow-ups use the dispatcher skill too")

        // A block, exactly as the engineering-lead skill writes one, and the loop it opens:
        // read it back, hand it to a session, resolve it, tell the waiting lead.
        precondition(Blocks.load(root: root).isEmpty, "no gate hit, no blocks folder")
        let blockFile = Blocks.root(in: root).appendingPathComponent("github-token.md")
        try! fm.createDirectory(at: Blocks.root(in: root), withIntermediateDirectories: true)
        try! """
        ---
        id: github-token
        kind: block
        title: "GitHub needs a personal access token"
        status: open
        session: \(leadID.uuidString.lowercased())
        task: wire-auth
        url: https://github.com/settings/tokens/new?scopes=repo
        action: "Create a token with repo scope and authenticate the GitHub MCP with it."
        ---

        The subagent finished the local work and cannot push.

        ## Needed from you

        - [ ] Generate the token and paste it back.

        ## Steps

        1. Open the token page with repo scope ticked.
        2. Authenticate the GitHub MCP with the pasted token.
        """.write(to: blockFile, atomically: true, encoding: .utf8)

        let block = Blocks.load(root: root).first!
        precondition(block.waiting && block.session == leadID && block.task == "wire-auth")
        precondition(block.link?.host == "github.com", "the page the user has to be on")
        precondition(block.body.contains("Generate the token"), "the checklist is what the user reads")
        precondition(block.body.contains("Authenticate the GitHub MCP"),
                     "SRE's procedure rides along for the FDE to deliver one step at a time")
        let guide = NotebookFormat.unblockPrompt(block: block, agent: .claude)
        precondition(guide.contains("fde-dev") && guide.contains(".notebook/blocks/github-token.md"),
                     "the guiding session is the FDE skill, pointed at the file it flips to done")
        precondition(echo(AgentCommand.quoted(guide)) == guide, "block prompt mangled by the shell")

        // A proposal shares the folder, the list and the button — it differs in who the
        // button reaches, and in that nothing is sitting blocked behind it.
        try! """
        ---
        id: add-checkout
        kind: proposal
        title: "Add a shared checkout flow"
        status: open
        session: ""
        task: launch-beta
        action: "Add the checkout project and decompose it into tasks."
        ---

        The roadmap promises checkout and no project covers it.

        ## What it would add

        - One project: `checkout`.
        """.write(to: Blocks.root(in: root).appendingPathComponent("add-checkout.md"),
                  atomically: true, encoding: .utf8)
        let proposal = Blocks.load(root: root).first { $0.isProposal }!
        precondition(proposal.waiting && proposal.session == nil, "nothing waits behind a proposal")
        let approval = NotebookFormat.unblockPrompt(block: proposal, agent: .claude)
        precondition(approval.contains("product") && approval.contains(".notebook/blocks/add-checkout.md"),
                     "approving a proposal goes back to product, not to an engineer")
        precondition(!block.isProposal
                     && NotebookFormat.unblockPrompt(block: block, agent: .claude).contains("fde-dev"),
                     "a gate still reaches the forward-deployed engineer")

        Blocks.resolve(block)
        let cleared = Blocks.load(root: root).first { $0.id == block.id }!
        precondition(!cleared.waiting, "resolving a block is one frontmatter edit")
        precondition(cleared.title == block.title && cleared.action == block.action,
                     "and touches nothing else in the file")
        precondition(NotebookFormat.unblockedMessage(block: cleared).contains(block.title),
                     "the waiting lead is told which block cleared")

        precondition(!NotebookEditor.hasConflict(loaded: "same", disk: "same"))
        precondition(NotebookEditor.hasConflict(loaded: "mine", disk: "agent"),
                     "an agent edit must not be overwritten by a stale editor")

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
