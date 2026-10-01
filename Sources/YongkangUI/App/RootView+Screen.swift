import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // MARK: - Work area

    @ViewBuilder func screen(for project: ProjectModel) -> some View {
        if project.missing {
            // Its folder was renamed or deleted: an empty read of it is not a new project.
            VStack(spacing: 8) {
                Image(systemName: "questionmark.folder").font(.system(size: 22)).foregroundStyle(Theme.tx4)
                Text("Can’t find this project").font(Typography.body).foregroundStyle(Theme.tx2)
                Text(project.directory.path).font(Typography.caption).foregroundStyle(Theme.tx3)
                Button("Remove from Yongkang") { close(project) }.padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        } else if let empty = needsIntake, empty.hasFiles, !empty.setupStarted {
            // A folder that already holds a project has nothing to ask: its code says what it is for.
            // Once per run, so closing that session lands on the board's rerun, not a new session.
            Theme.bg.task { model.go(to: empty.startNotebookSetup(nil, agent: agent)) }
        } else if let empty = needsIntake, !empty.hasFiles {
            // An empty project has nothing to click, so it asks what it is instead.
            ProjectIntake(project: empty.value) { description in
                model.go(to: empty.startNotebookSetup(description, agent: agent))
            }
        } else if model.selection == .board {
            boardView(for: project)
        } else if model.selection == .agents {
            ProjectAgentsPage(
                project: project.value,
                rows: project.value.agentRows(summary: project.summary, asking: model.attention),
                summary: project.summary, open: { model.selection = $0 },
                openBoard: { model.go(to: Destination(section: .board, route: .board)) },
                newAgent: { model.startingAgent = true })
        } else if case .memory(let id)? = model.selection {
            MemoryPage(
                project: project.value, selected: id,
                select: { model.selection = .memory($0) },
                edit: { url in model.selection = .entry(NotebookEntry.id(for: url)) },
                add: { milestone in model.add(.memory, to: project, under: .project(milestone)) })
        } else if model.selection == .skills {
            SkillsPage(project: project.directory)
        } else if let card = scopedCard(in: project, kind: .project) {
            ProjectDetail(
                card: card, cards: project.cards, repos: project.services(of: card),
                assigned: project.assignedTaskIDs, showDone: model.showDone,
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) },
                agents: agentChoice,
                assign: { tasks, agent in model.assign(tasks, in: project, agent: agent) },
                run: { card in model.runServices(project.services(of: card), in: project) },
                openTask: { task in model.selection = .task(task.id) }
            )
            .id(card.id)
        } else if let card = scopedCard(in: project, kind: .task) {
            TaskDetail(
                card: card, cards: project.cards, assigned: project.assignedTaskIDs,
                working: workers(on: card.id, in: project),
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) },
                agents: agentChoice,
                assign: { tasks, agent in model.assign(tasks, in: project, agent: agent) },
                discard: project.discardable(card.id).map { task in { model.discard(task, in: project) } },
                check: { worker in
                    model.section = .agents
                    model.selection = worker.route
                }
            )
            .id(card.id)
        } else if let card = scopedPageCard(in: project) {
            NotebookEntryDetail(
                card: card, cards: project.cards,
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) }
            )
            .id(card.id)
        } else if let watched = model.selectedAgent(in: project) {
            let pane = model.selection?.pane(of: watched.id) ?? .session
            AgentPage(
                session: watched, project: project.value,
                row: project.value.agentRows(summary: project.summary, asking: model.attention)
                    .first { $0.route == .session(watched.id) },
                content: {
                    switch pane {
                    case .session:
                        // A session clearing a gate gets the page that gate names beside it, so
                        // the instruction and the screen it is about are one glance apart.
                        if let link = project.value.gate(of: watched)?.link {
                            HSplitView {
                                terminal(for: watched).frame(minWidth: 420)
                                GuideBrowser(url: link).frame(minWidth: 360)
                            }
                        } else {
                            terminal(for: watched)
                        }
                    case .page:
                        SessionPage(url: NotebookFormat.page(of: watched.id, in: project.notebookRoot))
                    }
                })
        } else if let found = model.selectedSubagent(in: project) {
            terminal(for: found.session, showing: found.subagent)
        } else if let member = model.selectedMember(in: project) {
            TeamMemberDetail(
                member: member,
                file: Team.file(for: member.name, root: project.notebookRoot),
                directory: project.directory,
                running: runningAgents(of: member, in: project),
                openSubagent: { session, subagent in
                    model.selection = .subagent(session: session.id, id: subagent.id)
                }
            )
            .id(member.id)
        } else if let block = selectedBlock(in: project), block.isDemo {
            DesignDemo(
                block: block, cards: project.cards,
                waiting: project.waitingSession(for: block),
                approve: { revision in
                    model.go(to: project.approveDemo(block, revision: revision, agent: agent))
                    model.reload()
                },
                note: draft(for: block.id, in: project).note,
                revise: {
                    let note = project.reviewDrafts[block.id]?.note ?? ""
                    model.go(to: project.requestDemoChanges(block, note: note, agent: agent))
                },
                serve: { await model.serve(block, in: project) }
            )
            .id(block.id)
        } else if let block = selectedBlock(in: project) {
            BlockDetail(
                block: block, cards: project.cards,
                waiting: project.waitingSession(for: block),
                notebookRoot: project.notebookRoot,
                start: { model.go(to: project.startUnblock(block, agent: agent)) },
                revise: { model.go(to: project.openProposal(block, approve: false, agent: agent)) },
                resolve: {
                    Blocks.resolve(block)
                    model.reload()
                }
            )
            .id(block.id)
        } else if let task = reviewedTask(in: project) {
            // Approving stays on the task: the list on screen is the session's, and the next
            // task waiting may belong to another one.
            taskReview(task, in: project).id(task.id)
        } else if let path = reviewPath {
            let summary = project.summary
            // A file a task's worker claimed is reviewed as part of that task: comments on
            // its lines join that task's feedback, and the bar is that task's decision.
            let owner = path.isEmpty ? nil : summary.tasks.first { $0.files.contains { $0.path == path } }
            ChangeReview(
                project: project.value, changes: project.repo.changes, head: project.repo.head,
                branch: project.repo.branch,
                path: path, summary: summary,
                select: { model.selection = .review(file: $0) },
                commit: { await commit($0, in: project) },
                task: owner, draft: draft(for: owner?.id ?? "", in: project),
                openTask: { model.selection = .reviewTask($0) },
                approve: { message in
                    guard let owner else { return nil }
                    return await approve(owner, message: message, in: project)
                },
                requestChanges: { if let owner { model.go(to: project.requestChanges(on: owner, agent: agent)) } },
                discard: { if let owner { model.discard(owner, in: project, rerunningWith: agent) } })
        } else if let step = previewStep(in: project) {
            ProjectPreview(
                repo: step.repo, services: step.services,
                run: { model.runServices([step], in: project) }
            )
            .id(model.selection)
        } else if let entry = selectedEntry {
            NotebookEditor(entry: entry, alert: $model.alert).id(entry.id)
        } else if let session = model.selectedSession(in: project) {
            // A service runner: its terminal is all it has.
            terminal(for: session)
        } else {
            VStack(spacing: 8) {
                Image(systemName: model.section.systemImage).font(.system(size: 22))
                    .foregroundStyle(Theme.tx4)
                Text("Nothing selected in \(model.section.title).")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        }
    }

    /// A session's live terminal, borrowed from the registry for as long as this pane is up,
    /// with the CLI steered to `child`'s own view when there is one. A new host per session,
    /// so switching sessions hands the pane over rather than swapping what one host holds.
    @ViewBuilder private func terminal(for session: CodeSession, showing child: SubagentStatus? = nil) -> some View {
        if let view = model.terminals.view(for: session.id) {
            TerminalHost(terminal: view)
                .overlay(alignment: .top) {
                    if let message = model.terminals.childNavigation[session.id] {
                        Text(message).font(Typography.body).padding(10).background(Theme.panel)
                    }
                }
                .task(id: child?.id) { await model.terminals.showChild(child, in: session.id) }
                .id(session.id)
        }
    }

    /// Every Assign button starts on the toolbar's agent and can pick another for itself.
    private var agentChoice: AgentChoice {
        AgentChoice(
            initial: agent, found: model.foundAgents, untrusted: model.entered?.untrusted ?? [],
            lookUp: model.lookUpAgents)
    }

    private func boardView(for project: ProjectModel) -> some View {
        VStack(spacing: 0) {
            if let request = project.request {
                RequestBanner(
                    filed: project.filed,
                    openSession: { model.go(to: Destination(section: .agents, route: .session(request.session))) },
                    askForChanges: { project.requestOpen = true },
                    dismiss: { project.request = nil })
            }
            board(for: project)
        }
        // The board is where work is handed over, so it asks for the toolbar's agent to be let
        // into the folder the moment its record says no, rather than leaving "Run 0 ready" to
        // explain itself.
        .task(id: project.untrusted.contains(agent) ? project.id : nil) {
            model.askToTrust(agent, in: project)
        }
    }

    private func board(for project: ProjectModel) -> some View {
        NotebookBoard(
            cards: project.cards,
            blocks: project.snapshot.blocks,
            guided: project.guidedBlockIDs,
            assigned: project.assignedTaskIDs,
            reviewing: project.summary.waitingIDs,
            showDone: model.showDone,
            agents: agentChoice,
            assign: { tasks, agent in model.assign(tasks, in: project, agent: agent) },
            review: { model.go(to: project.startProductReview(agent: agent)) },
            openCard: { card in
                switch card.kind {
                case .task: model.selection = .task(card.id)
                case .project: model.selection = .project(card.id)
                default: model.selection = .page(card.id)
                }
            },
            openBlock: { model.selection = .block($0.id) },
            // The review is the Agents list's page, so the column goes with it — the same
            // swap the transcript makes the other way when it opens a task's board page.
            openReview: { card in
                model.section = .agents
                model.selection = .reviewTask(card.id)
            },
            remove: { card in model.remove(card, in: project) },
            fresh: Set(project.filed.map(\.id)),
            request: { project.requestOpen = true },
            dock: project.requestOpen ? AnyView(requestDock(for: project)) : nil,
            setup: setup(of: project)
        )
    }

    /// What the empty board says about the notebook's first write. Running wins even once the
    /// first files land, since the tasks are still on their way. Stopped only for a folder with
    /// something to read: an empty one goes back to the intake once its sessions are gone.
    private func setup(of project: ProjectModel) -> NotebookBoard.Setup? {
        if let running = project.runningSetup {
            return .running { model.go(to: Destination(section: .agents, route: .session(running.id))) }
        }
        guard !project.hasNotebook, project.hasFiles else { return nil }
        return .stopped { model.go(to: project.startNotebookSetup(nil, agent: agent)) }
    }

    private func requestDock(for project: ProjectModel) -> some View {
        RequestDock(
            root: project.directory, projects: model.taggable(from: project),
            followUp: project.requestFollowsUp,
            text: Binding {
                project.requestDraft
            } set: {
                project.requestDraft = $0
            },
            agents: agentChoice,
            send: { agent in model.request(project.requestDraft, in: project, agent: agent) },
            close: { project.requestOpen = false })
    }

    /// One task's review, opened from the task's row under its session.
    private func taskReview(_ task: SummaryTask, in project: ProjectModel) -> some View {
        TaskReview(
            task: task, summary: project.summary,
            directory: project.directory, cards: project.cards, team: project.snapshot.team,
            branch: project.repo.branch, head: project.repo.head, draft: draft(for: task.id, in: project),
            blocks: project.snapshot.blocks.filter { $0.waiting && !$0.isProposal && $0.task == task.id },
            openFile: { model.selection = .review(file: $0) },
            openBlock: { model.selection = .block($0.id) },
            startBlock: { model.go(to: project.startUnblock($0, agent: agent)) },
            approve: { await approve(task, message: $0, in: project) },
            requestChanges: { model.go(to: project.requestChanges(on: task, agent: agent)) },
            discard: { model.discard(task, in: project, rerunningWith: agent) }
        )
    }

    // MARK: - Selection

    /// A project with no notebook and no agent yet — the one case that starts a chat.
    private var needsIntake: ProjectModel? {
        model.entered.flatMap { $0.hasNotebook || !$0.sessions.isEmpty ? nil : $0 }
    }

    private var selectedEntry: NotebookEntry? {
        guard case .entry(let id) = model.selection, let project = model.entered else { return nil }
        return NotebookLoader.find(id, in: project.snapshot.entries)
    }

    private func scopedCard(in project: ProjectModel, kind: EntryKind) -> NotebookCard? {
        let id: String
        switch (model.selection, kind) {
        case (.project(let scoped)?, .project), (.task(let scoped)?, .task): id = scoped
        default: return nil
        }
        return project.cards.first { $0.id == id && $0.kind == kind }
    }

    private func scopedPageCard(in project: ProjectModel) -> NotebookCard? {
        guard case .page(let id) = model.selection else { return nil }
        return project.cards.first { $0.id == id }
    }

    /// The agents running this member's skill right now, wherever they were dispatched
    /// from — the way back from a standing agent into the work it is doing.
    private func runningAgents(
        of member: TeamMember,
        in project: ProjectModel
    ) -> [(session: CodeSession, subagent: SubagentStatus)] {
        project.sessions.flatMap { session in
            session.activeSubagents.filter { $0.member == member.name }
                .map { (session: session, subagent: $0) }
        }
    }

    /// Everyone on one task: the session it was assigned to, and any subagent that session
    /// dispatched for it — matched by the subagent's own name when it is read off disk.
    private func workers(on taskID: String, in project: ProjectModel) -> [TaskAgent] {
        project.value.agents(on: taskID)
    }

    func selectedBlock(in project: ProjectModel) -> UserBlock? {
        project.snapshot.blocks.first { model.selection == .block($0.id) }
    }

    /// The file a review selection points at, or "" for the review screen with nothing
    /// picked yet. Nil when the selection is not a review at all.
    private var reviewPath: String? {
        guard case .review(let file) = model.selection else { return nil }
        return file ?? ""
    }

    /// The repo a preview route points at, one per repo actually on disk, deduped across
    /// every notebook project. Nil if `selection` is not a preview.
    private func previewStep(in project: ProjectModel) -> ServicePlan? {
        guard case .preview(let directory) = model.selection else { return nil }
        return Service.dedupedByDirectory(project.services).first { $0.directory.path == directory.path }
    }

    func reviewedTask(in project: ProjectModel) -> SummaryTask? {
        guard case .reviewTask(let id) = model.selection else { return nil }
        return project.summary.tasks.first { $0.id == id }
    }

    private func draft(for taskID: String, in project: ProjectModel) -> Binding<ReviewDraft> {
        Binding(
            get: { project.reviewDrafts[taskID] ?? ReviewDraft() },
            set: { project.reviewDrafts[taskID] = $0 == ReviewDraft() ? nil : $0 })
    }
}
