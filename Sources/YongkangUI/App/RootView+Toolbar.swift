import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // MARK: - Where you are

    // The custom bar this replaced drew crumbs, then the screen's name, then its actions. The
    // window's title bar draws the same three things in the places macOS puts them: the name
    // on the title line, the crumb under it, the actions on the right. Nothing here measures
    // anything — the title bar truncates a long title before it moves an action, which is what
    // the old bar's `ViewThatFits` was written to do by hand.

    /// The title line: what is open, which is usually more specific than the section's name.
    func title(for project: ProjectModel?) -> String {
        guard let project else { return model.section.title }
        switch model.section {
        case .board:
            let scoped = model.selection?.card(in: project.cards)
            return scoped?.title ?? selectedBlock(in: project).flatMap { $0.isDemo ? $0.title : nil } ?? "Board"
        case .usage:
            return "Usage"
        case .agents:
            if isReviewingTree { return "Review changes" }
            if case .memory? = model.selection { return "Memory" }
            return model.selectedSubagent(in: project)?.subagent.description
                ?? reviewedTask(in: project)?.title
                ?? selectedBlock(in: project)?.title
                ?? model.selectedAgent(in: project)?.title
                ?? model.selectedSession(in: project)?.title
                ?? model.selectedMember(in: project)?.name ?? "Agents"
        }
    }

    /// The line under it: the project, or on the working tree the branch the changes are on,
    /// which is the thing you need to know before committing anything. With no project picked,
    /// how many there are and how many agents are on them.
    func subtitle(for project: ProjectModel?) -> String {
        guard let project else {
            let online = model.projects.reduce(0) { $0 + $1.value.onlineAgentCount }
            let count = model.projects.count
            return "\(count) project\(count == 1 ? "" : "s") · \(online) agent\(online == 1 ? "" : "s") online"
        }
        return isReviewingTree ? (project.repo.branch ?? project.name) : project.name
    }

    /// The whole working tree, rather than one task's review — the only page whose actions
    /// are git's rather than the section's.
    var isReviewingTree: Bool {
        if case .review = model.selection { return true }
        return false
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder func toolbar(for project: ProjectModel?) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) { listToggle }
        ToolbarItemGroup(placement: .primaryAction) {
            if let project { actions(for: project) }
            newAgentButton
        }
    }

    /// The one action every screen has: put an agent on a task, in any project.
    private var newAgentButton: some View {
        Button {
            model.startingAgent = true
        } label: {
            Label("New Agent", systemImage: "plus")
        }
        .buttonStyle(.consolePrimary)
        .help("Put an agent on a task (⌘N)")
    }

    /// The list column's switch. The split view's own is removed in `RootView` so there is
    /// only ever one. ⌘\ is not bound here: it is View → Hide List, so it works on a screen
    /// whose toolbar has scrolled this button out of reach. One binding, one place.
    private var listToggle: some View {
        Button {
            listHidden.toggle()
        } label: {
            Label(listHidden ? "Show list" : "Hide list", systemImage: "sidebar.left")
        }
        .help(listHidden ? "Show list (⌘\\)" : "Hide list (⌘\\)")
    }

    @ViewBuilder private func actions(for project: ProjectModel) -> some View {
        switch model.section {
        case .board:
            if let demo = selectedBlock(in: project).flatMap({ $0.isDemo ? $0 : nil }) {
                NotebookStyle.pill(
                    demo.waiting ? "demo · waiting on you" : "approved",
                    demo.waiting ? Theme.amber : Theme.green, live: demo.waiting)
            }
            if let scoped = model.selection?.card(in: project.cards), scoped.kind == .project {
                boardProgress(scoped, in: project)
            }
            completedToggle
            addMenu(for: project)
            Button {
                model.go(to: project.startProductReview(agent: agent))
            } label: {
                Label("Product review", systemImage: "sparkles")
            }
            .buttonStyle(.console)
        case .agents:
            if isReviewingTree {
                if let head = project.repo.head {
                    Text(head).font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Button {
                    model.refreshChanges(force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.console)
            } else {
                providerPicker
                addMenu(for: project)
                if let found = model.selectedSubagent(in: project) {
                    Button {
                        model.selection = .session(found.session.id)
                    } label: {
                        Label("Parent session", systemImage: "terminal")
                    }
                    .buttonStyle(.console)
                }
            }
        case .usage:
            EmptyView()
        }
    }

    private func boardProgress(_ card: NotebookCard, in project: ProjectModel) -> some View {
        let tasks = project.cards.filter { $0.kind == .task && $0.project == card.id }
        let done = tasks.filter { $0.status == "done" }.count
        return HStack(spacing: 9) {
            MeterBar(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count))
                .frame(width: 96)
            Text("\(done)/\(tasks.count)").font(Typography.mono).foregroundStyle(Theme.tx2)
        }
    }

    private var providerPicker: some View {
        AgentPicker(
            agent: $agent, found: model.foundAgents, lookUp: model.lookUpAgents, purpose: "Agent for new sessions")
    }

    private var completedToggle: some View {
        Button {
            model.showDone.toggle()
        } label: {
            Label(
                model.showDone ? "Hide completed" : "Completed",
                systemImage: model.showDone ? "eye.slash" : "eye")
        }
        .buttonStyle(.consoleGhost)
    }

    private func addMenu(for project: ProjectModel) -> some View {
        Menu {
            Section("Session") {
                Button(agent.displayName, systemImage: agent.systemImage) {
                    model.selection = project.addSession(agent)
                    model.section = .agents
                }
                OtherAgentMenu(title: "Other Agent", agent: agent, found: model.foundAgents) { other in
                    model.selection = project.addSession(other)
                    model.section = .agents
                }
            }
            Section("Team") {
                Button("Team Member…", systemImage: "person.badge.plus") { addingAgent = true }
                    .disabled(!project.hasNotebook)
            }
            Section("Notebook") {
                Button("Roadmap Entry…", systemImage: "map") { model.add(.roadmap, to: project) }
                Button("Milestone…", systemImage: "shippingbox") { model.add(.project, to: project) }
                Button("Task…", systemImage: "checkmark.circle") { model.add(.task, to: project) }
                Button("Memory…", systemImage: "brain") { model.add(.memory, to: project) }
                    .disabled(project.notebookProject(for: model.selection) == nil)
            }
            Divider()
            Button("Describe New Feature…", systemImage: "text.bubble") {
                model.go(to: project.startProduct("describe", agent: agent))
            }
            .disabled(!project.hasNotebook)
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.directory])
            }
            Button("Close Project", systemImage: "xmark") { close(project) }
        } label: {
            Label("New", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 62)
    }
}
