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
    func title(for project: ProjectModel) -> String {
        switch model.section {
        case .overview: return "Overview"
        case .board:
            let scoped = model.selection?.card(in: project.snapshot.cards)
            return scoped?.title ?? selectedBlock(in: project).flatMap { $0.isDemo ? $0.title : nil } ?? "Board"
        case .agents:
            guard model.selection != .usage else { return "Usage" }
            return model.selectedSubagent(in: project)?.subagent.description
                ?? model.selectedAgent(in: project)?.title
                ?? model.selectedSession(in: project)?.title
                ?? model.selectedMember(in: project)?.name ?? "Agents"
        case .review: return "Review changes"
        case .blocks: return "Blocks"
        }
    }

    /// The line under it: the project, or in Review the branch the changes are on, which is
    /// the thing you need to know before approving anything.
    func subtitle(for project: ProjectModel) -> String {
        model.section == .review ? (project.repo.branch ?? project.name) : project.name
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder func toolbar(for project: ProjectModel) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) { listToggle }
        ToolbarItemGroup(placement: .primaryAction) { actions(for: project) }
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
        case .overview:
            providerPicker
            completedToggle
            addMenu(for: project)
            Button {
                model.section = .board
                model.selection = .board
            } label: {
                Label("Assign work", systemImage: "bolt")
            }
            .buttonStyle(.consolePrimary)
        case .board:
            if let demo = selectedBlock(in: project).flatMap({ $0.isDemo ? $0 : nil }) {
                NotebookStyle.pill(
                    demo.waiting ? "demo · waiting on you" : "approved",
                    demo.waiting ? Theme.amber : Theme.green, live: demo.waiting)
            }
            if let scoped = model.selection?.card(in: project.snapshot.cards), scoped.kind == .project {
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
            addMenu(for: project)
            let watched = model.selectedAgent(in: project) ?? model.selectedSubagent(in: project)?.session
            if let watched, model.selectedSubagent(in: project) == nil {
                let panes = AgentPane.cases(lead: watched.isEngineeringLead)
                Picker("", selection: agentPane(watched)) {
                    ForEach(panes) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: panes.count == 3 ? 250 : 175)
            }
            if let found = model.selectedSubagent(in: project) {
                Button {
                    model.selection = .session(found.session.id)
                } label: {
                    Label("Parent session", systemImage: "terminal")
                }
                .buttonStyle(.console)
            }
        case .review:
            if let head = project.repo.head {
                Text(head).font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
            }
            Button {
                model.refreshChanges(force: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.console)
        case .blocks:
            completedToggle
        }
    }

    private func boardProgress(_ card: NotebookCard, in project: ProjectModel) -> some View {
        let tasks = project.snapshot.cards.filter { $0.kind == .task && $0.project == card.id }
        let done = tasks.filter { $0.status == "done" }.count
        return HStack(spacing: 9) {
            MeterBar(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count))
                .frame(width: 96)
            Text("\(done)/\(tasks.count)").font(Typography.mono).foregroundStyle(Theme.tx2)
        }
    }

    private var providerPicker: some View {
        Picker("", selection: $agent) {
            ForEach(AgentKind.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 320)
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
            }
            Section("Team") {
                Button("Agent…", systemImage: "person.badge.plus") { addingAgent = true }
                    .disabled(!project.hasNotebook)
            }
            Section("Notebook") {
                Button("Roadmap Entry…", systemImage: "map") { model.add(.roadmap, to: project) }
                Button("Project…", systemImage: "shippingbox") { model.add(.project, to: project) }
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
