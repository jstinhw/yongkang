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
        let codexLine = AgentCommand.line(directory: "/a", agent: .codex, prompt: "hi", sessionID: sid)
        precondition(codexLine.hasPrefix("cd '/a' && exec codex 'hi"),
                     "codex never understands --session-id, so the flag is never passed")
        precondition(codexLine.contains(AgentCommand.marker(sid)),
                     "the prompt carries the id instead — the only join from a row to its rollout")
        precondition(!AgentCommand.line(directory: "/a", agent: .claude, prompt: "hi", sessionID: sid)
                        .contains(AgentCommand.marker(sid)),
                     "claude has the flag and needs no marker in what the user reads")
        precondition(AgentKind.claude.skillInvocation("product", arguments: "review") == "/product review")
        precondition(AgentKind.codex.skillInvocation("product", arguments: "review") == "$product review")
        precondition(AgentKind.claude.skillInvocation("product", arguments: "describe") == "/product describe")
        precondition(AgentKind.codex.skillInvocation("product", arguments: "describe") == "$product describe")
        let productPrompt = NotebookFormat.productPrompt(arguments: "review", sessionID: sid, agent: .claude)
        precondition(productPrompt.contains("/product review")
                     && productPrompt.contains("Session id: \(sid.uuidString.lowercased())"),
                     "Product needs its session id so Blocks can return to its transcript")
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
        let leadLog = ClaudeTranscripts.transcriptURL(sessionID: sessionID, projectDirectory: tmp,
                                                      claudeHome: claudeHome)
        try! #"{"type":"tool_result","tool_use_id":"toolu_done"}"#
            .write(to: leadLog, atomically: true, encoding: .utf8)

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
        precondition(leadLog.path == sessionFolder.path + ".jsonl" && !leadLog.hasDirectoryPath,
                     "a lead is watched through the file beside its subagents' folder, not a folder")

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

        // A session is several selections, not one: its own transcript by default, a lead's
        // lanes, and the live terminal under the tag its PTY is already mounted on.
        let paneSession = UUID()
        precondition(AgentPane.of(Tag.transcript(paneSession), session: paneSession) == .transcript,
                     "an agent row lands on its transcript, the way a subagent row does")
        precondition(AgentPane.of(Tag.lanes(paneSession), session: paneSession) == .lanes)
        precondition(AgentPane.of(paneSession.uuidString, session: paneSession) == .session,
                     "the session stays reachable for anyone who wants to type at it")
        precondition(AgentPane.of(Tag.transcript(UUID()), session: paneSession) == nil,
                     "another session's tag is not this one's pane")
        precondition(AgentPane.cases(lead: true) == [.transcript, .lanes, .session]
                     && AgentPane.cases(lead: false) == [.transcript, .session],
                     "only a lead has specialists to show lanes of")
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
            // The opening prompt as `AgentCommand.line` actually writes it: the marker is
            // the whole join, so the fixture quotes the real one rather than a stand-in.
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"do the thing\n\n\#(AgentCommand.marker(codexSession))"}]}}"#,
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
        precondition(CodexTranscripts.transcriptURL(sessionID: codexSession, projectDirectory: tmp,
                                                    codexHome: codexHome)?.lastPathComponent
                     == "rollout-lead.jsonl",
                     "a Codex lead is watched through its own rollout, not one it spawned")
        precondition(CodexTranscripts.transcriptURL(sessionID: UUID(), projectDirectory: tmp,
                                                    codexHome: codexHome) == nil,
                     "a thread not on disk yet has no transcript to read, rather than the wrong one")
        try! (((try! String(contentsOf: child, encoding: .utf8))
               + "\n" + #"{"type":"event_msg","payload":{"type":"task_complete"}}"#))
            .write(to: child, atomically: true, encoding: .utf8)
        precondition(CodexTranscripts.isRunning(child) == false, "the last marker written wins")

        let codexLines = CodexTranscripts.transcript(at: child)
        precondition(codexLines.map(\.label) == ["Task", "Tool", "Result", "Reply"],
                     "reasoning and the duplicate event_msg lines are dropped")
        precondition(codexLines.map(\.text) == ["Message Type: NEW_TASK", "exec(ls)", "one file", "Done"])

        // What the header tells the reader: an agent that has replied is theirs to answer,
        // one mid-tool-call is not, and a dead process is neither.
        precondition(AgentState.of(lines: codexLines, exited: false) == .waiting)
        precondition(AgentState.of(lines: codexLines.dropLast(), exited: false) == .working)
        precondition(AgentState.of(lines: [], exited: false) == .starting)
        precondition(AgentState.of(lines: codexLines, exited: true) == .exited)

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
        wip.sessions[0].exited = true
        precondition(wip.assignedTaskIDs == ["c"],
                     "an exited lead no longer blocks dependency dispatch")

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

        // A transcript is mostly tool calls; the viewer keeps the brief and the replies and
        // collapses everything between them into one line, the way Claude Code prints it.
        let raw = [
            TranscriptLine(label: "Task", text: "Verify the four states"),
            TranscriptLine(label: "Tool", text: "Skill(command: qa-dev, args: )"),
            TranscriptLine(label: "Tool", text: "Grep(pattern: todo)"),
            TranscriptLine(label: "Result", text: "3 matches"),
            TranscriptLine(label: "Tool", text: "Read(file_path: page.tsx)"),
            TranscriptLine(label: "Result", text: "120 lines"),
            TranscriptLine(label: "Tool", text: "Bash(command: pg_ctl start)"),
            TranscriptLine(label: "Result", text: "could not start server", isError: true),
            TranscriptLine(label: "Reply", text: "Local Postgres is up on 55432.")
        ]
        let steps = TranscriptSteps.steps(raw)
        precondition(steps.map(\.kind) == [.task, .skill, .work, .say],
                     "a run of tool work collapses into one step between the readable ones")
        precondition(steps[1].text == "Skill(qa-dev)", "a skill keeps its own line, named")
        precondition(TranscriptSteps.skillName("Skill(args: redesign-add-todo-flow, skill: qa-dev)")
                     == "Skill(qa-dev)",
                     "the name comes from the field called skill, not from whichever sorts first")
        precondition(TranscriptSteps.steps([TranscriptLine(label: "Result", text: "Launching skill")])
                     .isEmpty, "a result with no call in front of it is not a step")
        precondition(steps[2].text == "Searched for 1 pattern, read 1 file, ran 1 shell command")
        precondition(steps[2].errors == 1, "a failed call is counted, not hidden")
        precondition(steps[2].detail.count == 6, "the calls stay behind the summary")
        precondition(TranscriptSteps.steps([]).isEmpty)

        // Invoking a skill pastes the whole skill document back in as a user message. It is
        // the agent's context, not something it did, and the Skill line already said so.
        let noisy = [
            TranscriptLine(label: "Task", text: "Use the qa-dev skill on redesign-todo-states"),
            TranscriptLine(label: "Tool", text: "Skill(skill: qa-dev)"),
            TranscriptLine(label: "Task", text: "Base directory for this skill: ~/.claude/skills/"
                + "qa-dev\n\nYou are QA on work that is claiming to be finished…"),
            TranscriptLine(label: "Task", text: "[SYSTEM NOTIFICATION - NOT USER INPUT] a hook ran"),
            TranscriptLine(label: "Task", text: "The coordinator sent a message while you were "
                + "working:\nQA failed, take another look at the empty state.")
        ]
        precondition(TranscriptSteps.steps(noisy).map(\.kind) == [.task, .skill, .note],
                     "the skill's own text and a system notification are dropped; a message "
                     + "from the lead is not")
        precondition(TranscriptSteps.steps(noisy)[2].text.hasPrefix("The coordinator sent"))
        let split = [
            TranscriptLine(label: "Task", text: "brief"),
            TranscriptLine(label: "Tool", text: "Read(file_path: a)"),
            TranscriptLine(label: "Task", text: "Base directory for this skill: x"),
            TranscriptLine(label: "Tool", text: "Read(file_path: b)")
        ]
        precondition(TranscriptSteps.steps(split).map(\.text) == ["brief", "Read 2 files"],
                     "a dropped injection does not cut the run around it in two")
        precondition(TranscriptSteps.aside("[Request interrupted by user]") != nil,
                     "anything unrecognised is shown rather than swallowed")

        // Picked tasks reach the lead as links, without duplicating their page descriptions.
        let picked = cards.filter { $0.kind == .task }
        precondition(picked.count >= 2)
        let leadID = UUID()
        let brief = NotebookFormat.engineeringPrompt(tasks: picked, sessionID: leadID, agent: .claude)
        precondition(brief.contains(leadID.uuidString.lowercased()),
                     "a lead has to know its own session id to route a block's answer back")
        precondition(brief.contains("engineering-lead"), "task batches invoke the dispatcher skill")
        for task in picked {
            precondition(brief.contains(task.id) && !brief.contains(task.title))
            precondition(brief.contains(".notebook/tasks/\(task.url.deletingPathExtension().lastPathComponent).md"),
                         "the lead needs a path it can open from the project root")
        }
        precondition(brief.contains("Session id: \(leadID.uuidString.lowercased())"),
                     "the lead needs its session id for blocks")
        precondition(echo(AgentCommand.quoted(brief)) == brief, "task brief mangled by the shell")

        // A follow-up batch reinvokes the same dispatcher with the same task detail.
        let follow = NotebookFormat.additionalTasksPrompt(tasks: picked, sessionID: leadID, agent: .claude)
        for task in picked {
            precondition(follow.contains(task.id) && !follow.contains(task.title))
        }
        precondition(follow.contains("engineering-lead"), "follow-ups use the dispatcher skill too")

        // The always-on lead: an empty batch is a standby brief, still carrying the id.
        let standby = NotebookFormat.engineeringPrompt(tasks: [], sessionID: leadID, agent: .claude)
        precondition(standby.contains("engineering-lead") && standby.contains("stand by"),
                     "no tasks means the lead confirms the team and waits")
        precondition(standby.contains("Session id: \(leadID.uuidString.lowercased())"))
        precondition(echo(AgentCommand.quoted(standby)) == standby, "standby brief mangled by the shell")

        // The team the lead routes by: shipped defaults, then `.notebook/team/` files win.
        func routing(_ members: [TeamMember]) -> [[String]] {
            members.map { [$0.name, $0.skills.joined(separator: ","), $0.owns] }
        }
        precondition(Team.load(root: root) == Team.defaults, "no team/ folder falls back to the shipped roster")
        Team.seedIfAbsent(root: root)
        precondition(routing(Team.load(root: root)) == routing(Team.defaults),
                     "seeding writes the shipped roster verbatim")
        Team.seedIfAbsent(root: root)
        precondition(Team.load(root: root).count == Team.defaults.count, "seeding a populated folder is a no-op")
        try! Team.write(TeamMember(name: "mobile-dev", skills: ["frontend-dev"],
                                   owns: "Native app screens", notes: "Ships the iOS target."), root: root)
        let roster = Team.load(root: root)
        precondition(roster.contains { $0.name == "mobile-dev" && $0.skills == ["frontend-dev"]
                        && $0.notes == "Ships the iOS target." },
                     "a hand-written agent file joins the roster, body and all")
        precondition(roster.count == Team.defaults.count + 1)

        // The skill behind a team member, as its page reads it: the block-list `allowed-tools`
        // the flat frontmatter reader cannot see, and a body that stops at the frontmatter.
        let skillText = """
        ---
        name: frontend-dev
        description: Build the user-facing half of one Yongkang task.
        allowed-tools:
          - Read
          - Write
        model: opus
        ---

        You are the frontend engineer on one task:

        - Read the task file first.
        """
        let skill = SkillDoc.parse(skillText, named: "whatever")
        precondition(skill.name == "frontend-dev", "the file names the skill, not the caller")
        precondition(skill.summary.hasPrefix("Build the user-facing half"))
        precondition(skill.tools == ["Read", "Write"],
                     "a block list of tools is read, and stops before the next field")
        precondition(skill.body.hasPrefix("You are the frontend engineer")
                     && skill.body.contains("- Read the task file first."),
                     "a bullet in the body is instructions, never another tool")
        precondition(SkillDoc.parse("no frontmatter here", named: "qa-dev")
                     == SkillDoc(name: "qa-dev", summary: "", tools: [],
                                 body: "no frontmatter here", url: nil),
                     "a skill file without frontmatter still reads as its instructions")
        precondition(SkillDoc.parse("---\nallowed-tools: [Read, Bash]\n---\nGo.", named: "x").tools
                     == ["Read", "Bash"], "an inline tool list reads the same way")

        // Who a running agent is: the lead names it `<task-id>-<skill>`, and the skill in
        // that name is what puts a person's face on every screen that shows the agent.
        func running(_ label: String, _ type: String) -> SubagentStatus {
            SubagentStatus(id: label, description: label, agentType: type, running: true,
                           transcriptURL: root).named(in: Team.defaults)
        }
        precondition(running("edit-todo-frontend-dev", "frontend-dev").displayName == "Allen")
        precondition(running("deploy-to-vercel-sre-dev", "sre-dev").displayName == "Chris")
        precondition(running("qa-dev: edit-todo", "qa-dev").displayName == "David",
                     "a label the lead punctuated its own way still names the right agent")
        precondition(running("Compact conversation", "general-purpose").displayName == "general-purpose",
                     "an agent no one on the team owns keeps its own name")
        precondition(running("edit-todo-frontend-dev", "frontend-dev").named(in: roster).member == "Allen",
                     "a hand-added agent sharing a skill never outranks the one shipped with it")
        // Codex nicknames a thread it spawns; the skill in the label is what the run is
        // filed under, so the tile has a colour and the ledger row groups under a person.
        let nicknamed = running("render_task_groups_frontend_dev", "Dewey")
        precondition(nicknamed.displayName == "Allen" && nicknamed.agentType == "frontend-dev",
                     "a provider's nickname never survives as an agent's role")

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
        stage: discussion
        session: \(leadID.uuidString.lowercased())
        task: launch-beta
        action: "Return to Product to review and refine the next move."
        ---

        The roadmap promises checkout and no project covers it.

        ## What it would add

        - One project: `checkout`.
        """.write(to: Blocks.root(in: root).appendingPathComponent("add-checkout.md"),
                  atomically: true, encoding: .utf8)
        let proposal = Blocks.load(root: root).first { $0.isProposal }!
        precondition(proposal.waiting && proposal.session == leadID && !proposal.proposalReady,
                     "a discussion notification links back to its Product transcript")
        let approval = NotebookFormat.unblockPrompt(block: proposal, agent: .claude)
        precondition(approval.contains("product") && approval.contains(".notebook/blocks/add-checkout.md"),
                     "a proposal can be resumed by product, not an engineer")
        let readyText = try! String(contentsOf: proposal.url, encoding: .utf8)
            .replacingOccurrences(of: "stage: discussion", with: "stage: ready")
        try! readyText.write(to: proposal.url, atomically: true, encoding: .utf8)
        precondition(Blocks.load(root: root).first { $0.isProposal }!.proposalReady,
                     "only a finalized proposal offers project creation")
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

        // Removing a project takes its tasks with it, and nothing else.
        let launch = cards.first { $0.id == "launch-beta" }!
        // Paths through the temp dir come back with /private resolved; compare like for like.
        func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().path }
        let owned = Set(NotebookFormat.owned(by: launch, in: cards).map(resolved))
        precondition(owned.contains(resolved(project.deletingLastPathComponent())),
                     "a project is its folder, not just project.md")
        precondition(owned.contains(resolved(first)) && owned.contains(resolved(tricky.url)),
                     "a project's tasks go with it")
        precondition(!owned.contains(resolved(run)), "run history is not the project's to delete")
        precondition(NotebookFormat.owned(by: tricky, in: cards) == [tricky.url],
                     "a task is one file")
        try! NotebookFormat.remove(launch, in: cards)
        let left = NotebookIndex.load(root: root)
        // Run history is an append-only log of what agents did, and is not navigable, so
        // it stays behind; every page a user can still open goes.
        precondition(!left.contains { $0.id == "launch-beta"
                        || ($0.kind != .run && $0.project == "launch-beta") },
                     "a page is left filed under a removed project")
        precondition(left.contains { $0.id == "bare" }, "and the rest of the notebook stays")

        // The open-project list lives in defaults, where anything could be sitting.
        let paths = ["/a/b", "/quote\"path", "/a b/c", tmp.path]
        precondition(OpenProjects.decode(OpenProjects.encode(paths)) == paths)
        precondition(OpenProjects.decode("").isEmpty)
        precondition(OpenProjects.decode("{\"not\": \"a list\"}").isEmpty)

        usage(in: tmp)

        print("notebook selftest ok")
    }

    /// The usage screen reads token counts out of the same transcripts the console
    /// watches. Both providers write them differently — Claude a delta per message, Codex
    /// a running total — and the Claude side is read incrementally, so a second pass over
    /// a file that grew must add the new lines and not re-count the old ones.
    private static func usage(in tmp: URL) {
        let fm = FileManager.default
        let dir = tmp.appendingPathComponent("usage")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        func at(_ clock: String) -> Date { AgentUsage.date("2026-09-03T\(clock):00.000Z")! }
        let noon = at("12:00")

        let claude = dir.appendingPathComponent("session.jsonl")
        func message(_ model: String, _ clock: String, out: Int) -> String {
            """
            {"type":"assistant","timestamp":"2026-09-03T\(clock):00.000Z","message":{"model":"\(model)",\
            "usage":{"input_tokens":10,"output_tokens":\(out),"cache_read_input_tokens":100,\
            "cache_creation_input_tokens":20}}}
            """
        }
        try! (message("claude-opus-5", "12:00", out: 5) + "\n")
            .write(to: claude, atomically: true, encoding: .utf8)
        let first = AgentUsage.samples(at: claude, .claude)
        precondition(first.count == 1 && first[0].at == noon)
        precondition(first[0].tally.output == 5 && first[0].tally.cacheRead == 100
                     && first[0].tally.total == 135)

        // Appended while the screen is open: the second read must pick up only the new lines.
        append(message("claude-opus-5", "12:30", out: 5) + "\n"
               + message("claude-haiku-4-5-20251001", "12:45", out: 3) + "\n", to: claude)
        let grown = AgentUsage.samples(at: claude, .claude)
        precondition(grown.count == 3, "an appended transcript is not re-counted")
        precondition(grown.filter { $0.model == "claude-opus-5" }.map(\.tally.output).reduce(0, +) == 10)

        // A half-written last line is left for the next pass rather than parsed as garbage.
        append(String(message("claude-opus-5", "12:50", out: 5).prefix(40)), to: claude)
        precondition(AgentUsage.samples(at: claude, .claude).count == 3,
                     "a partial line is not counted until its newline lands")

        // Windowing is what the range picker does: the same samples, narrowed by time.
        let spend = AgentSpend(id: "s", tag: "t", name: "Lead", role: "lead", provider: .claude,
                               running: true, samples: grown)
        precondition(spend.tally(since: nil).total == 403, "all time is every sample")
        precondition(spend.samples(since: at("12:40")).count == 1, "and a window is only what fits")
        precondition(spend.models(since: at("12:40")).keys.first == "claude-haiku-4-5-20251001")
        precondition(spend.topModel(since: nil) == "claude-opus-5",
                     "the model on a row is the one that spent most in the window")

        let codex = dir.appendingPathComponent("rollout.jsonl")
        func count(_ clock: String, _ input: Int, cached: Int, out: Int) -> String {
            """
            {"type":"event_msg","timestamp":"2026-09-03T\(clock):00.000Z","payload":{"type":"token_count",\
            "info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
            "cache_write_input_tokens":10,"output_tokens":\(out)}}}}
            """
        }
        try! ("""
        {"type":"turn_context","timestamp":"2026-09-03T12:00:00.000Z","payload":{"model":"gpt-5.6-luna"}}
        \(count("12:10", 100, cached: 80, out: 5))
        \(count("12:10", 100, cached: 80, out: 5))
        \(count("12:20", 300, cached: 250, out: 40))
        """ + "\n").write(to: codex, atomically: true, encoding: .utf8)
        let rollout = AgentUsage.samples(at: codex, .codex)
        precondition(rollout.count == 2, "a repeated running total is not a second turn")
        precondition(rollout.allSatisfy { $0.model == "gpt-5.6-luna" }, "the model comes off turn_context")
        // Differencing telescopes: the samples add back to the last total the file reported.
        let summed = rollout.map(\.tally).reduce(TokenTally(), +)
        precondition(summed.output == 40 && summed.cacheRead == 250 && summed.input == 50,
                     "Codex reports a running total, and its input already includes the cached half")
        precondition(rollout[1].tally.output == 35, "so a sample is the step, not the total")

        // The histogram slices the range into equal buckets and drops nothing inside it.
        let noonish = grown + rollout
        let hour = AgentUsage.histogram(noonish, range: .hour, now: at("13:00"))
        precondition(hour.count == UsageRange.hour.buckets)
        precondition(hour.map(\.total).reduce(0, +) == noonish.map(\.tally.total).reduce(0, +),
                     "every sample inside the range lands in exactly one bucket")
        precondition(hour[0].byModel["claude-opus-5"] == 135, "and lands in the right one")
        precondition(hour[6].byModel["claude-opus-5"] == 135 && hour[9].byModel["claude-haiku-4-5-20251001"] == 133)
        let stale = AgentUsage.histogram(noonish, range: .hour, now: at("18:00"))
        precondition(stale.map(\.total).reduce(0, +) == 0, "and nothing older than the range shows at all")
        // A sample landing on the window's own edge belongs in the last bucket, not nowhere.
        let edge = AgentUsage.histogram([UsageSample(at: at("13:00"), model: "m", tally: grown[0].tally)],
                                        range: .hour, now: at("13:00"))
        precondition(edge.last?.total == 135)
        precondition(AgentUsage.histogram([], range: .all, now: noon).isEmpty,
                     "an all-time view of nothing draws no bars rather than dividing by zero")

        // The ledger is what makes the numbers outlive the app: sessions are not restored
        // on relaunch, so without it a reopened project shows nothing however much its
        // agents spent.
        let notebook = dir.appendingPathComponent(".notebook")
        precondition(!UsageLedger.record([spend], root: notebook),
                     "a project with no notebook is not given one just to file usage in")
        try! fm.createDirectory(at: notebook, withIntermediateDirectories: true)
        precondition(UsageLedger.record([spend], root: notebook))
        precondition(!UsageLedger.record([spend], root: notebook),
                     "and an unchanged ledger is not rewritten, because the poll calls this")

        let remembered = UsageLedger.load(root: notebook)
        precondition(remembered.count == 1 && remembered[0].id == spend.id)
        precondition(remembered[0].name == "Lead" && remembered[0].role == "lead")
        precondition(remembered[0].tally(since: nil).total == spend.tally(since: nil).total,
                     "what an agent spent survives the run that read it")
        precondition(remembered[0].tag.isEmpty, "but its session is gone, so nothing opens")
        // 12:00 and 12:30 are one opus hour; 12:45 is a haiku hour of its own.
        precondition(remembered[0].samples.count == 2, "kept by the hour, not by the turn")
        precondition(remembered[0].samples.allSatisfy {
            $0.at.timeIntervalSince1970.truncatingRemainder(dividingBy: 3_600) == 0
        }, "and filed on the hour mark")

        // Usage only accumulates, so a re-read that comes back short — a truncated or
        // rotated transcript — must not erase the hour it had already recorded.
        let truncated = AgentSpend(id: spend.id, tag: "t", name: "Lead", role: "lead",
                                   provider: .claude, running: false, samples: [grown[0]])
        UsageLedger.record([truncated], root: notebook)
        precondition(UsageLedger.load(root: notebook)[0].tally(since: nil).total
                     == spend.tally(since: nil).total, "a short re-read keeps the fuller record")

        // A provider's agent id is only unique inside the session that spawned it, so the
        // spend that carries it has to be scoped — it is both a list key and a ledger row,
        // and two sessions really do hand out the same one.
        let shared = SubagentStatus(id: "a3a603000d158ff03", description: "qa", agentType: "qa-dev",
                                    running: false, transcriptURL: claude)
        var twin = Project(directory: tmp, entries: [])
        twin.sessions = [
            CodeSession(id: UUID(), title: "Engineering Lead", icon: "s", line: "claude",
                        agent: .claude, subagents: [shared]),
            CodeSession(id: UUID(), title: "Engineering Lead 2", icon: "s", line: "claude",
                        agent: .claude, subagents: [shared]),
        ]
        let ids = AgentUsage.spends(in: twin).map(\.id)
        precondition(Set(ids).count == ids.count, "the same agent id under two leads is two rows")

        // A second agent joins the ledger rather than replacing the first.
        let other = AgentSpend(id: "codex-1", tag: "t", name: "Backend", role: "backend-dev",
                               provider: .codex, running: false, samples: rollout)
        UsageLedger.record([other], root: notebook)
        let both = UsageLedger.load(root: notebook)
        precondition(both.count == 2 && both.contains { $0.provider == .codex },
                     "and each agent keeps its own provider")

        // Plan limits come out of Claude Code's own config cache, which is not an API —
        // a shape it does not recognise has to read as "nothing to show", never as a crash.
        let config = dir.appendingPathComponent("claude.json")
        try! """
        {"oauthAccount":{"organizationType":"claude_pro"},"cachedUsageUtilization":{\
        "fetchedAtMs":1788260110832,"utilization":{\
        "five_hour":{"utilization":42,"resets_at":"2026-09-01T15:50:00.296167+00:00"},\
        "seven_day":{"utilization":3,"resets_at":"2026-09-07T14:00:00+00:00"},\
        "seven_day_opus":null,\
        "spend":{"used":{"amount_minor":250,"exponent":2},"limit":{"amount_minor":10000,"exponent":2}}}}}
        """.write(to: config, atomically: true, encoding: .utf8)
        let quota = AgentUsage.claudeQuota(configURL: config)!
        precondition(quota.plan == "claude_pro")
        precondition(quota.windows.map(\.percent) == [42, 3], "a null window is skipped, not zeroed")
        precondition(quota.windows[0].resetsAt != nil && quota.windows[1].resetsAt != nil,
                     "both ISO shapes parse, with and without fractional seconds")
        precondition(quota.credits?.value == "$2.50 of $100.00")
        precondition(AgentUsage.claudeQuota(configURL: dir.appendingPathComponent("nope.json")) == nil)

        precondition(AgentUsage.short(999) == "999" && AgentUsage.short(1_500) == "1.5K"
                     && AgentUsage.short(45_000) == "45K" && AgentUsage.short(2_400_000) == "2.4M")
        precondition(AgentUsage.modelName("claude-haiku-4-5-20251001") == "haiku-4-5")
        precondition(AgentUsage.modelName("gpt-5.6-luna") == "gpt-5.6-luna")
        // Two versions of one model must not draw as the same colour, or a stacked bar
        // says how much went to Opus without saying which Opus.
        let shades = AgentUsage.palette(for: ["claude-opus-5", "claude-opus-4-7", "claude-sonnet-5"])
        precondition(shades["claude-opus-5"] != shades["claude-opus-4-7"])
        precondition(shades["claude-opus-5"] == AgentUsage.modelTint("claude-opus-5"),
                     "and the biggest spender in a family keeps the family's own colour")
        precondition(AgentUsage.until(noon.addingTimeInterval(8_100), now: noon) == "2h 15m")
        precondition(AgentUsage.until(noon.addingTimeInterval(-60), now: noon) == nil,
                     "a window that already rolled over says nothing rather than a negative")
    }

    /// Writes to the end of a file the way an agent's transcript grows: open, seek, write.
    private static func append(_ text: String, to url: URL) {
        let handle = try! FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try! handle.seekToEnd()
        try! handle.write(contentsOf: Data(text.utf8))
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
