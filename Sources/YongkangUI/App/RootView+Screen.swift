import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // MARK: - Work area

    @ViewBuilder func screen(for project: ProjectModel) -> some View {
        if let empty = needsIntake {
            // An empty project has nothing to click, so it asks what it is instead.
            ProjectIntake(project: empty.value) { description in
                addSession(
                    agent, to: empty,
                    prompt: NotebookFormat.onboardingPrompt(description: description),
                    title: "Notebook Setup")
            }
        } else if model.selection == .overview {
            Overview(
                project: project.value, changes: project.repo.changes, head: project.repo.head,
                go: {
                    model.section = $0
                    model.selection = $1
                },
                assign: {
                    model.section = .board
                    model.selection = .board
                })
        } else if model.selection == .board {
            boardView(for: project)
        } else if model.selection == .usage {
            UsageBoard(project: project.value, open: { model.selection = $0 })
        } else if let card = scopedCard(in: project, kind: .project) {
            ProjectDetail(
                card: card, cards: project.snapshot.cards, directory: project.directory,
                assigned: project.assignedTaskIDs, showDone: model.showDone,
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) },
                assign: { tasks in assign(tasks, in: project) },
                run: { card in runServices(card, in: project) },
                openTask: { task in model.selection = .task(task.id) }
            )
            .id(card.id)
        } else if let card = scopedCard(in: project, kind: .task) {
            TaskDetail(
                card: card, cards: project.snapshot.cards, assigned: project.assignedTaskIDs,
                working: workers(on: card.id, in: project),
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) },
                assign: { tasks in assign(tasks, in: project) },
                check: { session, subagent in
                    model.section = .agents
                    model.selection = .subagent(session: session.id, id: subagent.id)
                }
            )
            .id(card.id)
        } else if let card = scopedPageCard(in: project) {
            NotebookEntryDetail(
                card: card, cards: project.snapshot.cards,
                open: { url in model.selection = .entry(NotebookEntry.id(for: url)) }
            )
            .id(card.id)
        } else if let watched = model.selectedAgent(in: project) {
            switch model.selection?.pane(of: watched.id) {
            case .lanes:
                EngineeringLeadBoard(
                    session: watched, cards: project.snapshot.cards, blocks: project.snapshot.blocks,
                    team: project.snapshot.team,
                    openTask: {
                        model.section = .board
                        model.selection = .task($0)
                    },
                    openSubagent: { subagent in model.selection = .subagent(session: watched.id, id: subagent.id) },
                    openBlock: {
                        model.section = .blocks
                        model.selection = .block($0.id)
                    }
                )
            case .session:
                // The session's terminal is mounted underneath.
                Color.clear.overlay(alignment: .top) {
                    if let message = model.childNavigation[watched.id] {
                        Text(message).font(Typo.text(12)).padding(10).background(Theme.panel)
                    }
                }
            default:
                SessionTranscript(
                    session: watched, cards: project.snapshot.cards, blocks: project.snapshot.blocks,
                    lines: model.agentTranscript,
                    source: Transcripts.url(of: watched, in: project.directory),
                    openTask: {
                        model.section = .board
                        model.selection = .task($0)
                    },
                    openBlock: {
                        model.section = .blocks
                        model.selection = .block($0.id)
                    },
                    openSubagent: { subagent in model.selection = .subagent(session: watched.id, id: subagent.id) },
                    send: { model.pendingInput[watched.id] = $0 }
                )
            }
        } else if let found = model.selectedSubagent(in: project) {
            Color.clear.overlay(alignment: .top) {
                if let message = model.childNavigation[found.session.id] {
                    Text(message).font(Typo.text(12)).padding(10).background(Theme.panel)
                }
            }
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
                block: block, cards: project.snapshot.cards,
                waiting: project.waitingSession(for: block),
                approve: { revision in
                    go(to: project.approveDemo(block, revision: revision))
                    model.reload()
                },
                revise: { go(to: project.openDesigner(block)) }
            )
            .id(block.id)
        } else if let block = selectedBlock(in: project) {
            BlockDetail(
                block: block, cards: project.snapshot.cards,
                waiting: project.waitingSession(for: block),
                start: { go(to: project.startUnblock(block, agent: agent)) },
                revise: { go(to: project.openProposal(block, approve: false, agent: agent)) },
                resolve: {
                    Blocks.resolve(block)
                    model.reload()
                }
            )
            .id(block.id)
        } else if let task = reviewedTask(in: project) {
            TaskReview(
                task: task, summary: project.summary,
                directory: project.directory, cards: project.snapshot.cards, team: project.snapshot.team,
                branch: project.repo.branch, head: project.repo.head, draft: draft(for: task.id, in: project),
                openFile: { model.selection = .review(file: $0) },
                approve: { approve(task, message: $0, in: project) },
                requestChanges: { requestChanges(on: task, in: project) }
            )
            .id(task.id)
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
                commit: { commit($0, in: project) },
                task: owner, draft: draft(for: owner?.id ?? "", in: project),
                openTask: { model.selection = .reviewTask($0) },
                approve: { message in owner.flatMap { approve($0, message: message, in: project) } },
                requestChanges: { if let owner { requestChanges(on: owner, in: project) } })
        } else if let step = previewStep(in: project) {
            ProjectPreview(
                repo: step.repo, services: step.services,
                run: { runServices([step], in: project) }
            )
            .id(model.selection)
        } else if let entry = selectedEntry {
            NotebookEditor(entry: entry).id(entry.id)
        } else if model.selectedSession(in: project) != nil {
            // The terminal itself is mounted underneath; this pane stays out of its way.
            Color.clear
        } else {
            VStack(spacing: 8) {
                Image(systemName: model.section.systemImage).font(.system(size: 22))
                    .foregroundStyle(Theme.tx4)
                Text("Nothing selected in \(model.section.title).")
                    .font(Typo.text(13)).foregroundStyle(Theme.tx3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        }
    }

    private func boardView(for project: ProjectModel) -> some View {
        NotebookBoard(
            cards: project.snapshot.cards,
            blocks: project.snapshot.blocks,
            assigned: project.assignedTaskIDs,
            showDone: model.showDone,
            assign: { tasks in assign(tasks, in: project) },
            review: { go(to: project.startProductReview(agent: agent)) },
            openCard: { card in model.selection = .task(card.id) },
            openDemo: { demo in model.selection = .block(demo.id) },
            remove: { card in remove(card, in: project) }
        )
    }

    // MARK: - Selection

    func agentPane(_ session: CodeSession) -> Binding<AgentPane> {
        Binding(
            get: { model.selection?.pane(of: session.id) ?? .session },
            set: {
                model.selection = .session(session.id, pane: $0)
                model.reloadAgentTranscript()
            }
        )
    }

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
        return project.snapshot.cards.first { $0.id == id && $0.kind == kind }
    }

    private func scopedPageCard(in project: ProjectModel) -> NotebookCard? {
        guard case .page(let id) = model.selection else { return nil }
        return project.snapshot.cards.first { $0.id == id }
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

    /// Every subagent in this project that was dispatched for one task, whichever lead
    /// spawned it. The link is the subagent's own name, matched when it is read off disk.
    private func workers(on taskID: String, in project: ProjectModel) -> [(CodeSession, SubagentStatus)] {
        project.sessions.flatMap { session in
            session.subagents.filter { $0.taskID == taskID }.map { (session, $0) }
        }
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
    private func previewStep(
        in project: ProjectModel
    )
        -> (repo: String, directory: URL, services: [Service.Runnable])?
    {
        guard case .preview(let directory) = model.selection else { return nil }
        let steps = project.snapshot.cards.filter { $0.kind == .project }
            .flatMap { Service.plan(for: $0, in: project.directory) }
        return Service.dedupedByDirectory(steps).first { $0.directory.path == directory.path }
    }

    private func reviewedTask(in project: ProjectModel) -> SummaryTask? {
        guard case .reviewTask(let id) = model.selection else { return nil }
        return project.summary.tasks.first { $0.id == id }
    }

    private func draft(for taskID: String, in project: ProjectModel) -> Binding<ReviewDraft> {
        Binding(
            get: { project.reviewDrafts[taskID] ?? ReviewDraft() },
            set: { project.reviewDrafts[taskID] = $0 == ReviewDraft() ? nil : $0 })
    }
}
