import AppKit
import SwiftUI
import YongkangCore
import YongkangUI

/// Renders each screen offscreen to a PNG, from a fixed sample notebook. A layout that
/// clips, overflows or collapses is invisible in a compiler pass and obvious in a picture,
/// and the screens are too wide to check by launching the app on every change.
///
///     swift run shots /tmp/shots
enum DesignShots {
    @MainActor static func run(into directory: URL) {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeFixturePages()
        let project = sample()
        let agents = AgentChoice(initial: .claude, found: [.claude, .codex], lookUp: {})
        let lead = project.sessions[0]
        let worker = lead.subagents[0]

        // Nothing picked yet: the sidebar is the way in, and the screen says so.
        write(
            console(project, section: .agents, entered: false) {
                NothingPicked(hasProjects: true, create: {}, add: {})
            }, "empty", into: directory)

        write(
            NewProjectForm(
                parent: project.directory.deletingLastPathComponent(), agent: .claude,
                found: [.claude, .codex], lookUp: {}, create: { _, _, _ in }, cancel: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg),
            "new-project", into: directory, width: 900)

        // The agent picker's list, which a popover draws in a window of its own, so the sheet's
        // shot never has it open. Two of the four found, so the fold below them shows.
        write(
            AgentList(agent: .constant(.claude), found: [.claude, .codex], close: {})
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg),
            "agent-picker", into: directory, width: 900)

        write(
            console(project, section: .board) {
                NotebookBoard(
                    cards: project.cards, blocks: project.blocks,
                    assigned: ["show-agent-tree"], reviewing: ["transcript-steps"],
                    showDone: false, agents: agents,
                    assign: { _, _ in }, review: {}, openCard: { _ in },
                    openBlock: { _ in }, openReview: { _ in }, remove: { _ in })
            }, "board", into: directory)

        // The window's own minimum, which is where fixed-width columns run out of room
        // first. A screen that clips here clips on a real laptop.
        write(
            console(project, section: .board) {
                NotebookBoard(
                    cards: project.cards, blocks: project.blocks,
                    assigned: ["show-agent-tree"], reviewing: ["transcript-steps"],
                    showDone: false, agents: agents,
                    assign: { _, _ in }, review: {}, openCard: { _ in },
                    openBlock: { _ in }, openReview: { _ in }, remove: { _ in })
            }, "board-narrow", into: directory, width: 1120)

        // The gate itself. Both panes are live pages in the app; offscreen they render as
        // the frames, which is enough to catch the layout going wrong.
        write(
            console(project, section: .board) {
                DesignDemo(
                    block: project.blocks.first { $0.isDemo }!, cards: project.cards,
                    waiting: lead, approve: { _ in }, revise: {})
            }, "demo", into: directory)

        // The same screen at the window's minimum width, where its two panes run out of room
        // first. The demo's title and its pill are the window's title bar now, not the screen's.
        write(
            console(project, section: .board) {
                DesignDemo(
                    block: project.blocks.first { $0.isDemo }!, cards: project.cards,
                    waiting: lead, approve: { _ in }, revise: {})
            }, "demo-narrow", into: directory, width: 1120)

        // An agent on its transcript, and one answering a question in its terminal — the pane
        // offscreen is the frame a real terminal is borrowed into.
        for (name, session, pane, asking) in [
            ("lead", lead, AgentPane.transcript, String?.none),
            ("session", project.sessions[1], AgentPane.transcript, "Allow Bash(swift test)?"),
        ] {
            write(
                console(project, section: .agents, selection: .session(session.id, pane: pane)) {
                    AgentPage(
                        session: session, project: project, summary: ChangeSummary(),
                        row: project.agentRows(summary: ChangeSummary()).first { $0.route == .session(session.id) },
                        pane: pane, asking: asking, source: URL(fileURLWithPath: "/tmp/\(name).jsonl"),
                        select: { _ in }, open: { _ in }, stop: {},
                        content: { SessionTranscript(session: session, lines: transcript(), send: { _ in }) })
                }, name, into: directory)
        }

        // A task under its session in Agents, as a click on its green row opens it: its review,
        // with the session's other tasks beside it in the list. Fixture files rather than this
        // repo's, so the docs' copy of this shot changes only when the screen does.
        let result = finished(project, task: "pull-blockers", in: directory)
        let resultSummary = ChangeSummary.of(
            result,
            changes: [
                FileChange(
                    path: "Sources/YongkangCore/Notebook/LeadCoordination.swift", added: 46, removed: 9,
                    untracked: false),
                FileChange(path: "Sources/YongkangCore/Git/GitClient.swift", added: 12, removed: 3, untracked: false),
            ])
        func review(_ task: SummaryTask) -> TaskReview {
            TaskReview(
                task: task, summary: resultSummary, directory: result.directory, cards: result.cards,
                team: Team.defaults, branch: "feature/agent-tree", head: "51b0740 Show all agents",
                draft: .constant(ReviewDraft()),
                blocks: result.blocks.filter { $0.waiting && !$0.isProposal && $0.task == task.id },
                openFile: { _ in }, openBlock: { _ in }, startBlock: { _ in },
                approve: { _ in nil }, requestChanges: {})
        }
        // The narrow one also hovers a rail item, whose label draws over the list column.
        if let waiting = resultSummary.tasks.first(where: { $0.id == "pull-blockers" }) {
            for (name, width, hovering) in [
                ("agents", CGFloat(1440), nil), ("agents-narrow", 1180, ConsoleSection.board),
            ] {
                write(
                    console(
                        result, section: .agents, summary: resultSummary, hovering: hovering,
                        selection: .reviewTask(waiting.id)
                    ) { review(waiting) }, name, into: directory, width: width)
            }
        }

        // One project's agents side by side, with pull-blockers finished so every column has a card.
        write(
            console(result, section: .agents, summary: resultSummary, selection: .agents) {
                ProjectAgentsPage(
                    project: result, rows: result.agentRows(summary: resultSummary), summary: resultSummary,
                    ready: result.readyTasks, agents: agents, open: { _ in }, openBoard: {},
                    start: { _, _ in }, newAgent: {})
            }, "agents-project", into: directory)

        write(
            console(project, section: .agents, selection: .memory(nil)) {
                MemoryPage(project: project, selected: nil, select: { _ in }, edit: { _ in }, add: { _ in })
            }, "memory", into: directory)

        // A task held up by something only the user can do: the block's steps open the page.
        // Its brief is set here rather than in `pages`, whose files the board would list as news.
        if var blocked = resultSummary.tasks.first(where: { $0.id == "deploy-to-vercel" }) {
            blocked.body = """
                Put the console's landing page on Vercel, so the download link has somewhere to live.

                ## Done when

                - [ ] The project deploys from main
                - [ ] The download link resolves to the latest build
                """
            write(
                console(result, section: .agents, summary: resultSummary) { review(blocked) },
                "agents-blocked", into: directory)
        }

        write(
            console(project, section: .agents) {
                // Two skills on purpose: one owner of several is what the page has to shut by
                // default, and a single-skill member would prove nothing about that.
                TeamMemberDetail(
                    member: TeamMember(
                        name: "Allen", skills: ["designer", "product"],
                        owns: Team.defaults[0].owns,
                        notes: "Prefers the repo's own components over "
                            + "anything new."),
                    file: URL(fileURLWithPath: "/tmp/.notebook/team/allen.md"),
                    directory: project.directory,
                    running: [(lead, worker)], openSubagent: { _, _ in })
            }, "member", into: directory)

        // New Agent: a ready task from any open project, and what else it may read.
        write(
            NewAgentSheet(
                projects: [project] + neighbours().map(\.project), initial: project.id, agent: .claude,
                found: [.claude, .codex], lookUp: {}, startTask: { _, _, _, _ in }, startPrompt: { _, _, _, _ in },
                cancel: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg),
            "start-agent", into: directory)

        // The sheet behind New → Team Member…, drawn on its own: it is the one screen the console
        // layout does not frame, and the skill list is the part that overflows if it grows.
        write(
            NewAgentForm(
                directory: project.directory, taken: Team.defaults.map(\.name),
                save: { _ in }, incubate: { _ in }, cancel: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg),
            "new-agent", into: directory)

        write(
            console(project, section: .agents) {
                SubagentViewer(
                    session: lead, subagent: worker, lines: transcript(),
                    task: project.cards.first { $0.id == "show-agent-tree" },
                    openTask: { _ in })
            }, "transcript", into: directory)

        write(
            console(project, section: .board) {
                TaskDetail(
                    card: project.cards.first { $0.id == "show-agent-tree" }!,
                    cards: project.cards, assigned: ["show-agent-tree"],
                    working: [TaskAgent(session: lead), TaskAgent(session: lead, subagent: worker)],
                    open: { _ in }, agents: agents, assign: { _, _ in }, check: { _ in })
            }, "task", into: directory)

        write(
            console(project, section: .agents, selection: .block(project.blocks[0].id)) {
                BlockDetail(
                    block: project.blocks[0], cards: project.cards, waiting: lead,
                    start: {}, revise: {}, resolve: {})
            }, "block", into: directory)

        // The review screen is pointed at the repo this binary was built from, so the shot
        // is a real diff read through the real git plumbing rather than a mock.
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var here = Project(directory: repo, entries: [])
        here.cards = project.cards
        here.sessions = project.sessions
        here.blocks = project.blocks
        let status = readRepo(repo)
        let changes = status.changes
        let summary = ChangeSummary.of(here, changes: changes)
        write(
            console(here, section: .agents, summary: summary, selection: .review(file: nil)) {
                ChangeReview(
                    project: here, changes: changes, head: status.head,
                    branch: status.branch,
                    path: changes.first?.path ?? "", summary: summary,
                    select: { _ in }, commit: { _ in nil })
            }, "review", into: directory)

        // The screen the console lands on when a task finishes: the task, how the agent
        // checked it and what it did, over a real diff of this repo claimed by the fixture batch.
        let reviewed = finished(here, task: "pull-blockers", in: directory)
        let reviewedSummary = ChangeSummary.of(reviewed, changes: changes)
        if let task = reviewedSummary.tasks.first(where: { $0.id == "pull-blockers" }) {
            var draft = ReviewDraft()
            draft.comments = [
                ReviewComment(
                    path: "Sources/YongkangCore/Git/GitClient.swift", line: "104", code: "",
                    text: "Say which task the refused commit belonged to.")
            ]
            write(
                console(reviewed, section: .agents, summary: reviewedSummary, selection: .reviewTask(task.id)) {
                    TaskReview(
                        task: task, summary: reviewedSummary, directory: repo, cards: reviewed.cards,
                        team: Team.defaults, branch: status.branch, head: status.head,
                        draft: .constant(draft), blocks: [], openFile: { _ in }, openBlock: { _ in },
                        startBlock: { _ in }, approve: { _ in nil }, requestChanges: {})
                }, "handover", into: directory)
        }

        // Real numbers, off this machine's own transcripts for the repo the binary was
        // built from: the usage screen is nothing but its readers, so a shot drawn from a
        // fixture would prove the layout and nothing else.
        let real = realSessions(in: repo)
        write(
            console(real, section: .agents) {
                // The hour, not the default day: a machine whose agents ran this morning would
                // photograph an empty chart, which says nothing about whether it draws.
                UsageBoard(project: real, open: { _ in }, range: .hour)
            }, "usage", into: directory)

        print("shots written to \(directory.path)")
    }

    /// git's answer, waited for on the main thread. The shots stay synchronous on purpose:
    /// run from inside an async main-actor job, the run loop `write` spins never starts the
    /// screens' `.task`s, and a pane that loads in one is drawn empty.
    private static func readRepo(_ repo: URL) -> RepoStatus {
        // @unchecked: the semaphore is the handoff. The task writes `status` before it
        // signals and this thread reads it only after the wait returns, so the two never
        // touch the box at the same time.
        final class Answer: @unchecked Sendable { var status = RepoStatus() }
        let answer = Answer()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            answer.status = await RepoStatus.read(in: repo) ?? RepoStatus()
            done.signal()
        }
        done.wait()
        return answer.status
    }

    /// This repo's own agent sessions, as the console would hold them — every Claude Code
    /// transcript on disk for the folder the binary was built from, newest first, with the
    /// subagents each one spawned read the same way the running app reads them.
    private static func realSessions(in repo: URL) -> Project {
        var project = Project(directory: repo, entries: [])
        let folder = ClaudeTranscripts.projectFolder(projectDirectory: repo)
        let key: URLResourceKey = .contentModificationDateKey
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [key]))?.contentModificationDate ?? .distantPast
        }
        let files =
            ((try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [key])) ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { modified($0) > modified($1) }
            .prefix(4)
        project.sessions = files.enumerated().compactMap { index, url in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            return CodeSession(
                id: id, title: index == 0 ? "Claude Code" : "Claude Code \(index + 1)",
                icon: "sparkles", line: "claude", agent: .claude,
                subagents: ClaudeTranscripts.subagents(sessionID: id, projectDirectory: repo))
        }
        return project
    }

    /// The rail and the list column beside the screen, so a shot shows the real thing rather
    /// than a pane floating on its own. There is no bar above the screen any more: what used
    /// to be drawn here is the window's title bar, which no offscreen window has.
    ///
    /// The list column is framed at the width the split view opens it at, rather than drawn
    /// through the real `HSplitView`, whose divider a shot has no reason to show.
    @MainActor private static func console<Content: View>(
        _ project: Project, section: ConsoleSection,
        summary: ChangeSummary = ChangeSummary(),
        hovering: ConsoleSection? = nil, selection: Route? = nil, entered: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            Rail(
                section: .constant(section), badges: [.agents: Theme.amber],
                agentCount: project.onlineAgentCount, hovering: hovering
            )
            .zIndex(1)
            ProjectSidebar(
                section: section,
                projects: [SidebarProject(project: project, rows: project.agentRows(summary: summary))] + neighbours(),
                entered: entered ? project.id : nil, selection: selection,
                open: { _, _, _ in }, create: {}, add: {}, closeSession: { _, _ in }, close: { _ in }
            )
            .frame(width: Theme.listWidth)
            content()
        }
    }

    /// The other projects open beside the sample, so the sidebar is the list of every project it
    /// is: one with an agent at work and one finished, one held up by a token.
    private static func neighbours() -> [SidebarProject] {
        var sync = Project(directory: URL(fileURLWithPath: "/Users/you/sources/notebook-sync"), entries: [])
        sync.sessions = [
            CodeSession(title: "Claude Code", icon: "sparkles", line: "claude", agent: .claude, taskIDs: ["resume"]),
            CodeSession(title: "Codex", icon: "sparkles", line: "codex", agent: .codex, taskIDs: ["merge-runs"]),
        ]
        let synced = ChangeSummary(tasks: [
            SummaryTask(id: "resume", title: "Resume sync after sleep", status: "active"),
            SummaryTask(
                id: "merge-runs", title: "Merge runs without conflicts", status: "done",
                files: [FileChange(path: "Sources/Merge.swift", added: 140, removed: 22, untracked: false)]),
        ])
        var site = Project(directory: URL(fileURLWithPath: "/Users/you/sources/yongkang-site"), entries: [])
        let deploy = CodeSession(
            title: "Claude Code", icon: "sparkles", line: "claude", agent: .claude, taskIDs: ["deploy"])
        site.sessions = [deploy]
        site.blocks = [
            UserBlock(
                id: "/tmp/site-token.md", url: URL(fileURLWithPath: "/tmp/site-token.md"), slug: "site-token",
                title: "Vercel project token", status: "open", kind: "block", stage: "ready", session: deploy.id,
                action: "", link: nil, task: "deploy", resolution: "", body: "", before: nil, branch: "", revisions: [])
        ]
        let deploying = ChangeSummary(tasks: [SummaryTask(id: "deploy", title: "Deploy to Vercel", status: "blocked")])
        return [
            SidebarProject(project: sync, rows: sync.agentRows(summary: synced)),
            SidebarProject(project: site, rows: site.agentRows(summary: deploying)),
        ]
    }

    /// Drawn through a real offscreen window rather than `ImageRenderer`: the renderer
    /// silently draws nothing inside a `ScrollView`, which is most of every screen here.
    @MainActor private static func write<V: View>(
        _ view: V, _ name: String, into directory: URL,
        width: CGFloat = 1440
    ) {
        let size = NSRect(x: 0, y: 0, width: width, height: 900)
        let host = NSHostingView(
            rootView: AnyView(
                view.frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, .dark)))
        host.frame = size
        let window = NSWindow(
            contentRect: size, styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return print("could not render \(name)")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return print("could not encode \(name)")
        }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    /// The bodies the notebook read would have carried, so the pages that draw a card's text
    /// draw it here too — bodies, checklists and all — instead of rendering empty panes.
    private static let pages: [String: String] = [
        "show-agent-tree": """
        # Show all agents via tree expansion

        An agent that finishes drops out of its session's list, so a batch mid-flight reads \
        as though nothing is running. Keep every affiliated agent reachable under its \
        session and let the tree expand instead of filtering by completion.

        ## Done when

        - [x] Every affiliated agent stays visible under its session
        - [x] Collapsed roots are remembered, not completion statuses
        - [x] Codex descendants resolve through the full ancestor chain
        - [ ] The self-test covers the expansion state
        """,
        "vercel-token": """
        # Vercel project token

        The deploy needs a project-scoped token. The session is holding until this is \
        cleared.

        ## Steps

        1. Open the Vercel dashboard and pick the yongkang project
        2. Settings, then Tokens, then Create token — scope it to the project
        3. Paste it when the agent asks for it
        4. It verifies the deploy and carries on
        """,
    ]

    /// The same pages on disk, so the "Edit file" buttons and the file names point at
    /// something real.
    private static func writeFixturePages() {
        for (name, body) in pages {
            let text = "---\nid: \(name)\nstatus: active\n---\n\n" + body
            try? text.write(
                to: URL(fileURLWithPath: "/tmp/\(name).md"),
                atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Sample notebook

    /// The fixture with one task finished: its card done, a real task file to read, and its
    /// report filed with the verification a reviewer would read.
    private static func finished(_ project: Project, task id: String, in directory: URL) -> Project {
        var project = project
        let url = directory.appendingPathComponent("\(id).md")
        let body = """
            Link each block to the batch it holds up, so assigning a task brings its blockers along.

            ## Done when

            - [x] A block names the task it holds and the session waiting on it
            - [x] Assigning a task pulls in every unfinished blocker
            - [x] The board and the list agree on what a batch is
            """
        try? "---\nid: \(id)\nkind: task\nstatus: done\n---\n\n\(body)\n"
            .write(to: url, atomically: true, encoding: .utf8)
        project.cards = project.cards.map { card in
            guard card.id == id else { return card }
            return NotebookCard(
                id: card.id, url: url, kind: card.kind, title: card.title, status: "done",
                project: card.project, dependsOn: card.dependsOn, body: body)
        }
        for index in project.sessions.indices {
            guard var plan = project.sessions[index].coordination else { continue }
            plan.workers = plan.workers.map { work in
                guard work.taskID == id else { return work }
                var work = work
                work.state = "done"
                work.runtimeRunning = false
                work.result =
                    "Blocks now carry `task` and `session`; the loader resolves both and the "
                    + "batch expands through them. Self-test covers a missing and a cyclic blocker."
                work.verification =
                    "`make check` green; 281 tests, 12 known issues.\n\n"
                    + "Assigned a task with two open blockers: both joined the batch in dependency order."
                return work
            }
            project.sessions[index].coordination = plan
        }
        return project
    }

    private static func card(
        _ id: String, _ kind: EntryKind, _ title: String, _ status: String,
        project: String? = nil, dependsOn: [String] = [],
        designer: String = ""
    ) -> NotebookCard {
        NotebookCard(
            id: id, url: URL(fileURLWithPath: "/tmp/\(id).md"), kind: kind, title: title,
            status: status, project: project, dependsOn: dependsOn, designer: designer)
    }

    /// What the sample's agents have written down, for the Memory page: a decision about a task,
    /// a fact and a constraint, the way the format names and files them.
    private static let memory: [NotebookCard] = [
        NotebookCard(
            id: "2026-09-21-blocks-carry-task", url: URL(fileURLWithPath: "/tmp/2026-09-21-blocks-carry-task.md"),
            kind: .memory, title: "Blocks carry task and session", status: "", project: "build-ui-foundation",
            dependsOn: [], subject: "pull-blockers", memoryType: "decision",
            body: """
                A block names the task it holds up and the session waiting on it, so assigning a task \
                pulls in every unfinished block that names it.

                ## Why

                A batch could start a task whose token was still missing, and its session sat at a \
                prompt with nothing on screen saying why.

                ## How to apply

                Every block an agent writes carries `task:` and `session:`. A block naming neither \
                holds up the notebook, not a task.
                """),
        NotebookCard(
            id: "2026-09-18-fsevents-sleep", url: URL(fileURLWithPath: "/tmp/2026-09-18-fsevents-sleep.md"),
            kind: .memory, title: "FSEvents drops events across sleep", status: "", project: "build-ui-foundation",
            dependsOn: [], memoryType: "fact",
            body: "The 30-second safety read is what catches a Mac that slept. Keep it."),
        NotebookCard(
            id: "2026-09-10-macos-14", url: URL(fileURLWithPath: "/tmp/2026-09-10-macos-14.md"),
            kind: .memory, title: "macOS 14 is the floor", status: "", project: "ship-the-site",
            dependsOn: [], memoryType: "constraint",
            body: "`isolated deinit` needs macOS 15, so teardown stays explicit."),
    ]

    private static func sample() -> Project {
        var project = Project(directory: URL(fileURLWithPath: "/Users/you/sources/yongkang"), entries: [])
        project.cards =
            [
                card("ship-console", .roadmap, "Ship the agent console", "active"),
                card("build-ui-foundation", .project, "Build UI foundation", "active"),
                card(
                    "show-agent-tree", .task, "Show all agents via tree expansion", "active",
                    project: "build-ui-foundation"),
                card(
                    "pull-blockers", .task, "Pull project blockers into batches", "active",
                    project: "build-ui-foundation"),
                card(
                    "drop-finished", .task, "Drop finished work off the boards", "todo",
                    project: "build-ui-foundation"),
                card(
                    "design-task-diff", .task, "Design the task page's diff", "todo",
                    project: "build-ui-foundation", dependsOn: ["show-agent-tree"], designer: "Allen"),
                card(
                    "task-diff", .task, "Task page shows its own diff", "todo",
                    project: "build-ui-foundation", dependsOn: ["design-task-diff"]),
                card(
                    "design-review-pane", .task, "Design the review pane's verdict", "designing",
                    project: "build-ui-foundation", dependsOn: ["design-task-diff"], designer: "Allen"),
                card(
                    "review-pane", .task, "Review pane with the agent's verification", "todo",
                    project: "build-ui-foundation", dependsOn: ["design-review-pane", "task-diff"]),
                card(
                    "deploy-to-vercel", .task, "Deploy to Vercel", "blocked",
                    project: "build-ui-foundation", dependsOn: ["review-pane"]),
                card(
                    "transcript-steps", .task, "Lay a transcript out as steps", "done",
                    project: "build-ui-foundation"),
                // A second project, because one column never exercised the board running out
                // of room for the next one.
                card(
                    "ship-the-site", .project, "Put the landing page on Vercel", "todo",
                    dependsOn: ["build-ui-foundation"]),
                card(
                    "vercel-project", .task, "Connect this repo to Vercel", "todo",
                    project: "ship-the-site"),
                card(
                    "live-verify", .task, "Verify the live page and the download path", "todo",
                    project: "ship-the-site", dependsOn: ["vercel-project"]),
            ] + memory
        // What the notebook read would have put on each card. A page that draws a card's text
        // takes it from here, the way every screen takes it from the snapshot.
        project.cards = project.cards.map { card in
            guard let body = pages[card.id] else { return card }
            var filled = card
            filled.body = body
            return filled
        }
        let leadID = UUID()
        let transcript = URL(fileURLWithPath: "/tmp/agent.jsonl")
        var lead = CodeSession(
            id: leadID, title: "Claude Code", icon: "sparkles",
            line: "claude", agent: .claude,
            taskIDs: ["show-agent-tree", "pull-blockers", "deploy-to-vercel"])
        lead.subagents = [
            SubagentStatus(
                id: "tree", description: "show-agent-tree",
                agentType: "general-purpose", running: true, transcriptURL: transcript,
                taskID: "show-agent-tree"),
            SubagentStatus(
                id: "blockers", description: "pull-blockers",
                agentType: "general-purpose", running: false, transcriptURL: transcript,
                taskID: "pull-blockers"),
            SubagentStatus(
                id: "deploy", description: "deploy-to-vercel", agentType: "general-purpose",
                running: false, transcriptURL: transcript, taskID: "deploy-to-vercel"),
        ].map { $0.named(in: project.team) }
        // Reports as the work prompt asks for them. Token counts are fixture observations,
        // never a claim about a model.
        let now = Date()
        lead.coordination = LeadCoordination(
            workers: [
                LeadWork(
                    id: "show-agent-tree", taskID: "show-agent-tree", title: "Keep every agent visible",
                    paths: ["Sources/Yongkang/ChangeSummary.swift", "Sources/Yongkang/ChangeReview.swift"],
                    state: "running", agentID: "tree",
                    startedAt: now.addingTimeInterval(-540), updatedAt: now.addingTimeInterval(-35),
                    measuredTokens: 9800, measuredModel: "claude-sonnet-5", runtimeRunning: true),
                LeadWork(
                    id: "pull-blockers", taskID: "pull-blockers", title: "Link blockers to the assigned batch",
                    paths: [
                        "Sources/YongkangCore/Notebook/LeadCoordination.swift",
                        "Sources/YongkangCore/Git/GitClient.swift",
                    ],
                    state: "done", agentID: "blockers",
                    startedAt: now.addingTimeInterval(-600), finishedAt: now.addingTimeInterval(-120),
                    updatedAt: now.addingTimeInterval(-120), actualTokens: 7900,
                    report: "Blocker reader and self-test pass."),
                LeadWork(
                    id: "deploy-to-vercel", taskID: "deploy-to-vercel", title: "Prepare deployment",
                    state: "blocked", agentID: "deploy",
                    startedAt: now.addingTimeInterval(-720), finishedAt: now.addingTimeInterval(-600),
                    updatedAt: now.addingTimeInterval(-600), actualTokens: 2100,
                    report: "Blocked: Vercel project token. Setup steps are ready in Blocks."),
            ])
        project.sessions = [
            lead,
            CodeSession(title: "Product", icon: "sparkles", line: "claude", agent: .claude),
        ]
        project.blocks = [
            UserBlock(
                id: "/tmp/vercel-token.md", url: URL(fileURLWithPath: "/tmp/vercel-token.md"),
                slug: "vercel-token", title: "Vercel project token", status: "open",
                kind: "block", stage: "ready", session: leadID, action: "", link: URL(string: "https://vercel.com"),
                task: "deploy-to-vercel", resolution: "",
                body: "## Steps\n\n1. Open the Vercel dashboard and pick the project\n"
                    + "2. Settings, then Tokens, then Create token\n"
                    + "3. Paste it when the agent asks — it is never written down\n",
                before: nil, branch: "", revisions: []),
            UserBlock(
                id: "/tmp/offline.md", url: URL(fileURLWithPath: "/tmp/offline.md"),
                slug: "offline", title: "Offline notebook sync", status: "open",
                kind: "proposal", stage: "discussion", session: project.sessions.last?.id,
                action: "", link: nil, task: nil,
                resolution: "", body: "", before: nil, branch: "", revisions: []),
            demo(leadID),
        ]
        return project
    }

    /// A design waiting on the user, written the way the designer skill writes one.
    private static func demo(_ session: UUID) -> UserBlock {
        let body = """
            The task page grows a diff of its own work — one change on the project's demo,
            and the task that builds it waits on this.

            ## What changes

            - The file list sits under the criteria instead of in a separate tab.
            - Additions and deletions read as one column, not two panes.

            ## Revisions

            - v1 · two panes side by side · http://localhost:3100
            - v2 · one column, the file list under the criteria · http://localhost:3101
            """
        return UserBlock(
            id: "/tmp/design-task-diff-demo.md",
            url: URL(fileURLWithPath: "/tmp/design-task-diff-demo.md"),
            slug: "design-task-diff-demo", title: "Design the task page's diff",
            status: "open", kind: "demo", stage: "ready", session: session,
            action: "Approve the task-page diff, or say what is wrong with it.",
            link: URL(string: "http://localhost:3101"), task: "design-task-diff",
            resolution: "", body: body,
            before: URL(string: "http://localhost:3000"),
            branch: "demo/build-ui-foundation", revisions: Blocks.revisions(body))
    }

    private static func transcript() -> [TranscriptLine] {
        var lines: [TranscriptLine] = [
            TranscriptLine(
                label: "Task",
                text: "Agents disappear from their session once they finish, "
                    + "so a batch mid-flight reads as empty. Keep every affiliated agent reachable.")
        ]
        for file in ["App.swift", "ProjectList.swift", "Rail.swift", "Theme.swift"] {
            lines.append(TranscriptLine(label: "Tool", text: "Read(file_path: Sources/\(file))"))
            lines.append(TranscriptLine(label: "Result", text: "read \(file)"))
        }
        lines += [
            TranscriptLine(label: "Grep", text: ""),
            TranscriptLine(
                label: "Reply",
                text: "The list column and the work board both show "
                    + "subagents, so the filter belongs on the session itself rather than in each view."),
            TranscriptLine(label: "Tool", text: "Edit(file_path: Sources/Project.swift)"),
            TranscriptLine(label: "Result", text: "+4 −0"),
            TranscriptLine(label: "Tool", text: "Bash(command: make check)"),
            TranscriptLine(label: "Result", text: "Build complete! (4.67s)\nnotebook selftest ok"),
            TranscriptLine(label: "Tool", text: "Bash(command: swift test)"),
            TranscriptLine(label: "Result", text: "error: no such module 'XCTest'", isError: true),
            TranscriptLine(
                label: "Reply",
                text: "Four files changed and the self-test passes. "
                    + "Every Done when item is checked; the report is filed for your review."),
        ]
        return lines.filter { $0.label != "Grep" }
    }
}
