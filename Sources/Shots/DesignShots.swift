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
        let lead = project.sessions[0]
        let worker = lead.subagents[0]

        write(
            ProjectsHome(
                projects: [project], enter: { _ in },
                create: {}, add: {}, close: { _ in }),
            "fleet", into: directory)

        write(
            NewProjectForm(
                parent: project.directory.deletingLastPathComponent(),
                create: { _, _ in }, cancel: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg),
            "new-project", into: directory, width: 900)

        write(
            console(project, section: .overview, hovering: .blocks) {
                Overview(
                    project: project, changes: [], head: "51b0740 Show all agents",
                    go: { _, _ in }, assign: {})
            }, "overview", into: directory)

        write(
            console(project, section: .board) {
                NotebookBoard(
                    cards: project.cards, blocks: project.blocks,
                    assigned: ["show-agent-tree"], showDone: false,
                    assign: { _ in }, review: {}, openCard: { _ in },
                    openDemo: { _ in }, remove: { _ in })
            }, "board", into: directory)

        // The window's own minimum, which is where fixed-width columns run out of room
        // first. A screen that clips here clips on a real laptop.
        write(
            console(project, section: .board) {
                NotebookBoard(
                    cards: project.cards, blocks: project.blocks,
                    assigned: ["show-agent-tree"], showDone: false,
                    assign: { _ in }, review: {}, openCard: { _ in },
                    openDemo: { _ in }, remove: { _ in })
            }, "board-narrow", into: directory, width: 1120)

        // The gate itself. Both panes are live pages in the app; offscreen they render as
        // the frames, which is enough to catch the layout going wrong.
        write(
            console(project, section: .board) {
                DesignDemo(
                    block: project.blocks.first { $0.isDemo }!, cards: project.cards,
                    waiting: lead, approve: { _ in }, revise: {})
            }, "demo", into: directory)

        // With the top bar the app actually draws there: a long task title, a pill and an
        // action, which is where a title that will not yield pushes the buttons off.
        write(
            console(
                project, section: .board, crumbs: [project.name, "Board"],
                title: project.blocks.first { $0.isDemo }!.title,
                pill: AnyView(NotebookStyle.pill("demo · waiting on you", Theme.amber, live: true)),
                action: "Open task"
            ) {
                DesignDemo(
                    block: project.blocks.first { $0.isDemo }!, cards: project.cards,
                    waiting: lead, approve: { _ in }, revise: {})
            }, "demo-narrow", into: directory, width: 1120)

        write(
            console(project, section: .agents) {
                SessionTranscript(
                    session: lead, cards: project.cards, blocks: project.blocks,
                    lines: transcript(), source: URL(fileURLWithPath: "/tmp/lead.jsonl"),
                    openTask: { _ in }, openBlock: { _ in }, openSubagent: { _ in },
                    send: { _ in })
            }, "lead", into: directory)

        write(
            console(project, section: .agents) {
                SessionTranscript(
                    session: project.sessions[1], cards: project.cards,
                    blocks: project.blocks, lines: transcript(),
                    source: URL(fileURLWithPath: "/tmp/product.jsonl"),
                    openTask: { _ in }, openBlock: { _ in }, openSubagent: { _ in },
                    send: { _ in })
            }, "session", into: directory)

        write(
            console(project, section: .agents) {
                EngineeringLeadBoard(
                    session: lead, cards: project.cards, blocks: project.blocks,
                    team: Team.defaults,
                    openTask: { _ in }, openSubagent: { _ in }, openBlock: { _ in })
            }, "agents", into: directory)

        write(
            console(project, section: .agents) {
                EngineeringLeadBoard(
                    session: lead, cards: project.cards, blocks: project.blocks,
                    team: Team.defaults,
                    openTask: { _ in }, openSubagent: { _ in }, openBlock: { _ in })
            }, "agents-narrow", into: directory, width: 1180)

        var legacyLead = lead
        legacyLead.coordination = nil
        write(
            console(project, section: .agents) {
                EngineeringLeadBoard(
                    session: legacyLead, cards: project.cards, blocks: project.blocks,
                    team: Team.defaults,
                    openTask: { _ in }, openSubagent: { _ in }, openBlock: { _ in })
            }, "agents-legacy", into: directory)

        write(
            console(project, section: .agents) {
                EngineeringLeadBoard(
                    session: CodeSession(title: "Engineering Lead", icon: "sparkles", line: "codex"),
                    cards: [], blocks: [], team: Team.defaults,
                    openTask: { _ in }, openSubagent: { _ in }, openBlock: { _ in })
            }, "agents-standby", into: directory)

        write(
            console(project, section: .agents) {
                // Two skills on purpose: one owner of several is what the page has to shut by
                // default, and a single-skill member would prove nothing about that.
                TeamMemberDetail(
                    member: TeamMember(
                        name: "Allen", skills: ["frontend-dev", "qa-dev"],
                        owns: Team.defaults[0].owns,
                        notes: "Prefers the repo's own components over "
                            + "anything new."),
                    file: URL(fileURLWithPath: "/tmp/.notebook/team/allen.md"),
                    directory: project.directory,
                    running: [(lead, worker)], openSubagent: { _, _ in })
            }, "member", into: directory)

        // The sheet behind New → Agent…, drawn on its own: it is the one screen the console
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
                    working: [(lead, worker)], open: { _ in }, assign: { _ in },
                    check: { _, _ in })
            }, "task", into: directory)

        write(
            console(project, section: .blocks) {
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
        let changes = GitChanges.changes(in: repo)
        let summary = ChangeSummary.of(here, changes: changes)
        write(
            console(here, section: .review, changes: changes) {
                ChangeReview(
                    project: here, changes: changes, head: GitChanges.head(in: repo),
                    branch: GitChanges.branch(in: repo),
                    path: changes.first?.path ?? "", summary: summary,
                    select: { _ in }, commit: { _ in nil })
            }, "review", into: directory)

        // The screen the console lands on when a task finishes: the task, QA's verdict and
        // what each agent did, over a real diff of this repo claimed by the fixture batch.
        let reviewed = finished(here, task: "pull-blockers", in: directory)
        let reviewedSummary = ChangeSummary.of(reviewed, changes: changes)
        if let task = reviewedSummary.tasks.first(where: { $0.id == "pull-blockers" }) {
            var draft = ReviewDraft()
            draft.comments = [
                ReviewComment(
                    path: "Sources/Yongkang/GitChanges.swift", line: "104", code: "",
                    text: "Say which task the refused commit belonged to.")
            ]
            write(
                console(reviewed, section: .review, changes: changes) {
                    TaskReview(
                        task: task, summary: reviewedSummary, directory: repo, cards: reviewed.cards,
                        team: Team.defaults, branch: GitChanges.branch(in: repo), head: GitChanges.head(in: repo),
                        draft: .constant(draft), openFile: { _ in }, approve: { _ in nil }, requestChanges: {})
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
                id: id, title: index == 0 ? "Engineering Lead" : "Claude Code \(index + 1)",
                icon: "sparkles", line: "claude", agent: .claude,
                subagents: ClaudeTranscripts.subagents(sessionID: id, projectDirectory: repo))
        }
        return project
    }

    /// The same four columns every screen is drawn inside, so a shot shows the real thing
    /// rather than a pane floating on its own.
    private static func console<Content: View>(
        _ project: Project, section: ConsoleSection,
        changes: [FileChange] = [],
        hovering: ConsoleSection? = nil,
        crumbs: [String]? = nil, title: String? = nil,
        pill: AnyView? = nil, action: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            Rail(
                section: .constant(section), badges: [.blocks: Theme.amber], leave: {},
                agentCount: project.onlineAgentCount, hovering: hovering
            )
            .zIndex(1)
            ProjectList(
                section: section, project: project, selection: .constant(nil),
                showDone: false, changes: changes, assign: { _ in }, closeSession: { _ in },
                remove: { _ in })
            VStack(spacing: 0) {
                TopBar(
                    crumbs: crumbs ?? [project.name], title: title ?? section.title,
                    pill: pill
                ) {
                    Button("Completed") {}.buttonStyle(.consoleGhost)
                    if let action { Button(action) {}.buttonStyle(.console) }
                }
                content()
            }
        }
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

    /// The sample pages are written to /tmp so the screens read them the way they read a
    /// real notebook — bodies, checklists and all — instead of rendering empty panes.
    private static func writeFixturePages() {
        let pages: [String: String] = [
            "show-agent-tree": """
            # Show all agents via tree expansion

            An agent that finishes drops out of the lead's list, so a batch mid-flight reads \
            as though nothing is running. Keep every affiliated agent reachable under its \
            lead and let the tree expand instead of filtering by completion.

            ## Done when

            - [x] Every affiliated agent stays visible under its lead
            - [x] Collapsed roots are remembered, not completion statuses
            - [x] Codex descendants resolve through the full ancestor chain
            - [ ] The self-test covers the expansion state
            """,
            "vercel-token": """
            # Vercel project token

            sre-dev needs a project-scoped token before it can deploy. It is holding until \
            this is cleared.

            ## Steps

            1. Open the Vercel dashboard and pick the yongkang project
            2. Settings, then Tokens, then Create token — scope it to the project
            3. Paste it when the forward-deployed engineer asks for it
            4. It verifies the deploy and releases sre-dev
            """,
        ]
        for (name, body) in pages {
            let text = "---\nid: \(name)\nstatus: active\n---\n\n" + body
            try? text.write(
                to: URL(fileURLWithPath: "/tmp/\(name).md"),
                atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Sample notebook

    /// The fixture with one task through QA: its card done, a real task file to read, and
    /// its QA pass filed with the verdict a reviewer would read.
    private static func finished(_ project: Project, task id: String, in directory: URL) -> Project {
        var project = project
        let url = directory.appendingPathComponent("\(id).md")
        try? """
        ---
        id: \(id)
        kind: task
        status: done
        ---

        Link each block to the batch it holds up, so assigning a task brings its blockers along.

        ## Done when

        - [x] A block names the task it holds and the lead session waiting on it
        - [x] Assigning a task pulls in every unfinished blocker
        - [x] The board and the list agree on what a batch is
        """.write(to: url, atomically: true, encoding: .utf8)
        project.cards = project.cards.map { card in
            guard card.id == id else { return card }
            return NotebookCard(
                id: card.id, url: url, kind: card.kind, title: card.title, status: "done",
                project: card.project, dependsOn: card.dependsOn)
        }
        for index in project.sessions.indices {
            guard var plan = project.sessions[index].coordination else { continue }
            plan.workers = plan.workers.map { work in
                guard work.taskID == id else { return work }
                var work = work
                work.state = "done"
                work.runtimeRunning = false
                if work.skill == "qa-dev" {
                    work.result =
                        "Verdict **pass**. `swift run Yongkang --selftest` ok; `swift build` exit 0.\n\n"
                        + "Assigned a task with two open blockers: both joined the batch in dependency order. "
                        + "Not exercised: two leads racing for the same blocker."
                } else {
                    work.result =
                        "Blocks now carry `task` and `session`; the loader resolves both and the "
                        + "batch expands through them. Self-test covers a missing and a cyclic blocker."
                }
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

    private static func sample() -> Project {
        var project = Project(directory: URL(fileURLWithPath: "/Users/you/sources/yongkang"), entries: [])
        project.cards = [
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
                "review-pane", .task, "Review pane with a QA verdict", "todo",
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
        ]
        let leadID = UUID()
        let transcript = URL(fileURLWithPath: "/tmp/agent.jsonl")
        var lead = CodeSession(
            id: leadID, title: "Engineering Lead", icon: "sparkles",
            line: "claude", agent: .claude,
            taskIDs: ["show-agent-tree", "pull-blockers", "deploy-to-vercel"])
        lead.subagents = [
            SubagentStatus(
                id: "fe", description: "show-agent-tree-frontend-dev",
                agentType: "frontend-dev", running: true, transcriptURL: transcript,
                taskID: "show-agent-tree"),
            SubagentStatus(
                id: "qa", description: "pull-blockers-qa-dev", agentType: "qa-dev",
                running: true, transcriptURL: transcript, taskID: "pull-blockers"),
            SubagentStatus(
                id: "be", description: "pull-blockers-backend-dev",
                agentType: "backend-dev", running: false, transcriptURL: transcript,
                taskID: "pull-blockers"),
            SubagentStatus(
                id: "sre", description: "deploy-to-vercel-sre-dev", agentType: "sre-dev",
                running: false, transcriptURL: transcript, taskID: "deploy-to-vercel"),
        ].map { $0.named(in: project.team) }
        // Explicit preview observations; these context windows are fixture metadata,
        // never a claim about a model's capacity or a fallback used by the live app.
        let now = Date()
        lead.coordination = LeadCoordination(
            strategy:
                "Split three tasks into five subtasks. Run UI and blocker work together; queue each QA pass after its build. Deployment waits for setup.",
            parallelLimit: 2, estimatedTokens: 42000, estimatedMinutes: 24, updatedAt: now.addingTimeInterval(-35),
            contextSummary:
                "Keep task contracts, decisions and next steps. Save a checkpoint before replacing a worker’s context.",
            workers: [
                LeadWork(
                    id: "show-agent-tree-ui", taskID: "show-agent-tree", title: "Keep every worker visible",
                    skill: "frontend-dev", model: "gpt-5.6-terra",
                    reason:
                        "Allen owns the native UI. Bounded SwiftUI work suits the standard coding model; no shared files with the blocker reader.",
                    paths: ["Sources/Yongkang/ChangeSummary.swift", "Sources/Yongkang/ChangeReview.swift"],
                    state: "running", agentID: "fe", estimatedTokens: 16000, estimatedMinutes: 14,
                    startedAt: now.addingTimeInterval(-540), updatedAt: now.addingTimeInterval(-35),
                    contextTokens: 43000, contextWindow: 128000, contextSource: "Preview runtime metadata",
                    checkpoint:
                        "Preserve finished workers. Board and rail use session.subagents. Next: verify collapsed roots and narrow layout.",
                    measuredTokens: 9800, measuredModel: "gpt-5.6-terra", runtimeRunning: true),
                LeadWork(
                    id: "show-agent-tree-qa", taskID: "show-agent-tree", title: "Verify expansion and return states",
                    skill: "qa-dev", model: "gpt-5.6-luna",
                    reason: "David runs the existing checks and inspects the screenshots after UI work returns.",
                    dependsOn: ["show-agent-tree-ui"], estimatedTokens: 6000, estimatedMinutes: 5),
                LeadWork(
                    id: "pull-blockers-reader", taskID: "pull-blockers", title: "Link blockers to the assigned batch",
                    skill: "backend-dev", model: "gpt-5.6-terra",
                    reason: "Ben owns notebook loading; the reader is independent of the UI files.",
                    paths: ["Sources/Yongkang/LeadCoordination.swift", "Sources/Yongkang/GitChanges.swift"],
                    state: "review", agentID: "be", estimatedTokens: 11000, estimatedMinutes: 10,
                    startedAt: now.addingTimeInterval(-600), finishedAt: now.addingTimeInterval(-120),
                    updatedAt: now.addingTimeInterval(-120), actualTokens: 7900,
                    checkpoint: "Reader complete. Self-test passes; David is checking cross-session routing.",
                    report: "Returned: blocker reader and self-test pass. Independent QA is in progress."),
                LeadWork(
                    id: "pull-blockers-qa", taskID: "pull-blockers", title: "Check blocker routing",
                    skill: "qa-dev", model: "gpt-5.6-luna",
                    reason: "Focused verification uses the smaller model and the existing self-test.",
                    dependsOn: ["pull-blockers-reader"], paths: ["Sources/Yongkang/NotebookSelfTest.swift"],
                    state: "running", agentID: "qa",
                    estimatedTokens: 5000, estimatedMinutes: 5,
                    startedAt: now.addingTimeInterval(-90), updatedAt: now.addingTimeInterval(-20),
                    contextTokens: 19000, contextWindow: 128000, contextSource: "Preview runtime metadata",
                    measuredTokens: 1700, measuredModel: "gpt-5.6-luna", runtimeRunning: true),
                LeadWork(
                    id: "deploy-to-vercel-setup", taskID: "deploy-to-vercel", title: "Prepare deployment",
                    skill: "sre-dev", model: "gpt-5.6-terra",
                    reason: "Chris owns deployment. Work pauses until the project token is configured.",
                    state: "blocked", agentID: "sre", estimatedTokens: 4000, estimatedMinutes: 5,
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
                    + "3. Paste it when the engineer asks — it is never written down\n",
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
                text: "Agents disappear from the lead once they finish, "
                    + "so a batch mid-flight reads as empty. Keep every affiliated agent reachable."),
            TranscriptLine(label: "Tool", text: "Skill(skill: qa-dev)"),
            TranscriptLine(
                label: "Task",
                text: "Base directory for this skill: "
                    + "/Users/you/.claude/skills/qa-dev\n\nYou are QA on work that is claiming to "
                    + "be finished. Verify it against the task's own \"Done when\" list…"),
        ]
        for file in ["App.swift", "ProjectList.swift", "Rail.swift", "Theme.swift"] {
            lines.append(TranscriptLine(label: "Tool", text: "Read(file_path: Sources/\(file))"))
            lines.append(TranscriptLine(label: "Result", text: "read \(file)"))
        }
        lines += [
            TranscriptLine(label: "Grep", text: ""),
            TranscriptLine(
                label: "Reply",
                text: "The list column and the lead board both show "
                    + "subagents, so the filter belongs on the session itself rather than in each view."),
            TranscriptLine(label: "Tool", text: "Edit(file_path: Sources/Project.swift)"),
            TranscriptLine(label: "Result", text: "+4 −0"),
            TranscriptLine(label: "Tool", text: "Bash(command: swift build && swift run Yongkang --selftest)"),
            TranscriptLine(label: "Result", text: "Build complete! (4.67s)\nnotebook selftest ok"),
            TranscriptLine(label: "Tool", text: "Bash(command: swift test)"),
            TranscriptLine(label: "Result", text: "error: no such module 'XCTest'", isError: true),
            TranscriptLine(
                label: "Reply",
                text: "Four files changed and the self-test passes. "
                    + "Handing the task file and the diff to qa-dev — I do not review my own work."),
        ]
        return lines.filter { $0.label != "Grep" }
    }
}
