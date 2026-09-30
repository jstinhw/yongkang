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
        if model.showsUsage { return "Usage" }
        guard let project else { return model.section.title }
        switch model.section {
        case .board:
            let scoped = model.selection?.card(in: project.cards)
            // The sidebar's task rows open a block or a review without leaving the board.
            return scoped?.title ?? selectedBlock(in: project)?.title ?? reviewedTask(in: project)?.title ?? "Board"
        case .agents:
            if isReviewingTree { return "Review changes" }
            if case .memory? = model.selection { return "Memory" }
            if model.selection == .skills { return "Skills" }
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
            // Nothing new starts here: New Agent (⌘N) and the rest are the menu bar's, and a
            // project's terminal is the sidebar's.
            if let project { actions(for: project) }
        }
    }

    /// The list column's switch; dragging its edge shut is the other way. ⌘\ is not bound here: it is View → Hide List, so it works on a screen
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
            // Product review lives in the board's bar, beside Run: the toolbar adds and views.
            completedToggle
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
                if let found = model.selectedSubagent(in: project) {
                    Button {
                        model.selection = .session(found.session.id)
                    } label: {
                        Label("Parent session", systemImage: "terminal")
                    }
                    .buttonStyle(.console)
                }
            }
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
                model.showDone ? "Hide completed" : "Show completed",
                systemImage: model.showDone
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help(model.showDone ? "Hide completed tasks" : "Show completed tasks")
    }
}
