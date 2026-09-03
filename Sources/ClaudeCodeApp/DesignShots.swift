import SwiftUI
import AppKit

/// Renders each screen offscreen to a PNG, from a fixed sample notebook. A layout that
/// clips, overflows or collapses is invisible in a compiler pass and obvious in a picture,
/// and the screens are too wide to check by launching the app on every change.
///
///     swift run ClaudeCodeApp --shots /tmp/shots
enum DesignShots {
    @MainActor static func run(into directory: URL) {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeFixturePages()
        let project = sample()
        let lead = project.sessions[0]
        let worker = lead.subagents[0]

        write(ProjectsHome(projects: [project], agent: .constant(.claude),
                           enter: { _ in }, add: {}, close: { _ in }),
              "fleet", into: directory)

        write(console(project, section: .overview, hovering: .blocks) {
            Overview(project: project, changes: [], head: "51b0740 Show all agents",
                     go: { _, _ in }, assign: {})
        }, "overview", into: directory)

        write(console(project, section: .board) {
            NotebookBoard(cards: project.cards, assigned: ["show-agent-tree"], showDone: false,
                          assign: { _ in }, review: {}, openCard: { _ in }, remove: { _ in })
        }, "board", into: directory)

        write(console(project, section: .agents) {
            SessionTranscript(session: lead, cards: project.cards, blocks: project.blocks,
                              lines: transcript(), source: URL(fileURLWithPath: "/tmp/lead.jsonl"),
                              openTask: { _ in }, openBlock: { _ in }, openSubagent: { _ in },
                              send: { _ in })
        }, "lead", into: directory)

        write(console(project, section: .agents) {
            SessionTranscript(session: project.sessions[1], cards: project.cards,
                              blocks: project.blocks, lines: transcript(),
                              source: URL(fileURLWithPath: "/tmp/product.jsonl"),
                              openTask: { _ in }, openBlock: { _ in }, openSubagent: { _ in },
                              send: { _ in })
        }, "session", into: directory)

        write(console(project, section: .agents) {
            EngineeringLeadBoard(session: lead, cards: project.cards, blocks: project.blocks,
                                 openTask: { _ in }, openSubagent: { _ in }, openBlock: { _ in })
        }, "agents", into: directory)

        write(console(project, section: .agents) {
            SubagentViewer(session: lead, subagent: worker, lines: transcript(),
                           task: project.cards.first { $0.id == "show-agent-tree" },
                           openTask: { _ in })
        }, "transcript", into: directory)

        write(console(project, section: .board) {
            TaskDetail(card: project.cards.first { $0.id == "show-agent-tree" }!,
                       cards: project.cards, assigned: ["show-agent-tree"],
                       working: [(lead, worker)], open: { _ in }, assign: { _ in },
                       check: { _, _ in })
        }, "task", into: directory)

        write(console(project, section: .blocks) {
            BlockDetail(block: project.blocks[0], cards: project.cards, waiting: lead,
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
        write(console(here, section: .review, changes: changes) {
            ChangeReview(project: here, changes: changes, head: GitChanges.head(in: repo),
                         branch: GitChanges.branch(in: repo),
                         path: changes.first?.path ?? "", select: { _ in })
        }, "review", into: directory)

        print("shots written to \(directory.path)")
    }

    /// The same four columns every screen is drawn inside, so a shot shows the real thing
    /// rather than a pane floating on its own.
    private static func console<Content: View>(_ project: Project, section: ConsoleSection,
                                               changes: [FileChange] = [],
                                               hovering: ConsoleSection? = nil,
                                               @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Rail(section: .constant(section), badges: [.blocks: Theme.amber], leave: {},
                 hovering: hovering)
                .zIndex(1)
            ProjectList(section: section, project: project, selection: .constant(nil),
                        showDone: false, changes: changes, assign: { _ in }, closeSession: { _ in },
                        remove: { _ in })
            VStack(spacing: 0) {
                TopBar(crumbs: [project.name], title: section.title) {
                    Button("Completed") {}.buttonStyle(.consoleGhost)
                }
                content()
            }
        }
    }

    /// Drawn through a real offscreen window rather than `ImageRenderer`: the renderer
    /// silently draws nothing inside a `ScrollView`, which is most of every screen here.
    @MainActor private static func write<V: View>(_ view: V, _ name: String, into directory: URL) {
        let size = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)))
        host.frame = size
        let window = NSWindow(contentRect: size, styleMask: [.borderless],
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
            """
        ]
        for (name, body) in pages {
            let text = "---\nid: \(name)\nstatus: active\n---\n\n" + body
            try? text.write(to: URL(fileURLWithPath: "/tmp/\(name).md"),
                            atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Sample notebook

    private static func card(_ id: String, _ kind: EntryKind, _ title: String, _ status: String,
                             project: String? = nil, dependsOn: [String] = []) -> NotebookCard {
        NotebookCard(id: id, url: URL(fileURLWithPath: "/tmp/\(id).md"), kind: kind, title: title,
                     status: status, project: project, dependsOn: dependsOn)
    }

    private static func sample() -> Project {
        var project = Project(directory: URL(fileURLWithPath: "/Users/you/sources/yongkang"), entries: [])
        project.cards = [
            card("ship-console", .roadmap, "Ship the agent console", "active"),
            card("build-ui-foundation", .project, "Build UI foundation", "active"),
            card("show-agent-tree", .task, "Show all agents via tree expansion", "active",
                 project: "build-ui-foundation"),
            card("pull-blockers", .task, "Pull project blockers into batches", "active",
                 project: "build-ui-foundation"),
            card("drop-finished", .task, "Drop finished work off the boards", "todo",
                 project: "build-ui-foundation"),
            card("task-diff", .task, "Task page shows its own diff", "todo",
                 project: "build-ui-foundation", dependsOn: ["show-agent-tree"]),
            card("review-pane", .task, "Review pane with a QA verdict", "todo",
                 project: "build-ui-foundation", dependsOn: ["task-diff"]),
            card("deploy-to-vercel", .task, "Deploy to Vercel", "blocked",
                 project: "build-ui-foundation", dependsOn: ["review-pane"]),
            card("transcript-steps", .task, "Lay a transcript out as steps", "done",
                 project: "build-ui-foundation")
        ]
        let leadID = UUID()
        let transcript = URL(fileURLWithPath: "/tmp/agent.jsonl")
        var lead = CodeSession(id: leadID, title: "Engineering Lead", icon: "sparkles",
                               line: "claude", agent: .claude,
                               taskIDs: ["show-agent-tree", "pull-blockers", "deploy-to-vercel"])
        lead.subagents = [
            SubagentStatus(id: "fe", description: "show-agent-tree-frontend-dev",
                           agentType: "frontend-dev", running: true, transcriptURL: transcript,
                           taskID: "show-agent-tree"),
            SubagentStatus(id: "qa", description: "show-agent-tree-qa-dev", agentType: "qa-dev",
                           running: true, transcriptURL: transcript, taskID: "show-agent-tree"),
            SubagentStatus(id: "be", description: "pull-blockers-backend-dev",
                           agentType: "backend-dev", running: true, transcriptURL: transcript,
                           taskID: "pull-blockers"),
            SubagentStatus(id: "sre", description: "deploy-to-vercel-sre-dev", agentType: "sre-dev",
                           running: true, transcriptURL: transcript, taskID: "deploy-to-vercel")
        ]
        project.sessions = [lead,
                            CodeSession(title: "Product", icon: "sparkles", line: "claude", agent: .claude)]
        project.blocks = [
            UserBlock(id: "/tmp/vercel-token.md", url: URL(fileURLWithPath: "/tmp/vercel-token.md"),
                      slug: "vercel-token", title: "Vercel project token", status: "open",
                      kind: "block", stage: "ready", session: leadID, action: "", link: URL(string: "https://vercel.com"),
                      task: "deploy-to-vercel", resolution: "",
                      body: "## Steps\n\n1. Open the Vercel dashboard and pick the project\n"
                          + "2. Settings, then Tokens, then Create token\n"
                          + "3. Paste it when the engineer asks — it is never written down\n"),
            UserBlock(id: "/tmp/offline.md", url: URL(fileURLWithPath: "/tmp/offline.md"),
                      slug: "offline", title: "Offline notebook sync", status: "open",
                      kind: "proposal", stage: "discussion", session: project.sessions.last?.id,
                      action: "", link: nil, task: nil,
                      resolution: "", body: "")
        ]
        return project
    }

    private static func transcript() -> [TranscriptLine] {
        var lines: [TranscriptLine] = [
            TranscriptLine(label: "Task", text: "Agents disappear from the lead once they finish, "
                + "so a batch mid-flight reads as empty. Keep every affiliated agent reachable."),
            TranscriptLine(label: "Tool", text: "Skill(skill: qa-dev)"),
            TranscriptLine(label: "Task", text: "Base directory for this skill: "
                + "/Users/you/.claude/skills/qa-dev\n\nYou are QA on work that is claiming to "
                + "be finished. Verify it against the task's own \"Done when\" list…")
        ]
        for file in ["App.swift", "ProjectList.swift", "Rail.swift", "Theme.swift"] {
            lines.append(TranscriptLine(label: "Tool", text: "Read(file_path: Sources/\(file))"))
            lines.append(TranscriptLine(label: "Result", text: "read \(file)"))
        }
        lines += [
            TranscriptLine(label: "Grep", text: ""),
            TranscriptLine(label: "Reply", text: "The list column and the lead board both show "
                + "subagents, so the filter belongs on the session itself rather than in each view."),
            TranscriptLine(label: "Tool", text: "Edit(file_path: Sources/Project.swift)"),
            TranscriptLine(label: "Result", text: "+4 −0"),
            TranscriptLine(label: "Tool", text: "Bash(command: swift build && swift run ClaudeCodeApp --selftest)"),
            TranscriptLine(label: "Result", text: "Build complete! (4.67s)\nnotebook selftest ok"),
            TranscriptLine(label: "Tool", text: "Bash(command: swift test)"),
            TranscriptLine(label: "Result", text: "error: no such module 'XCTest'", isError: true),
            TranscriptLine(label: "Reply", text: "Four files changed and the self-test passes. "
                + "Handing the task file and the diff to qa-dev — I do not review my own work.")
        ]
        return lines.filter { $0.label != "Grep" }
    }
}
