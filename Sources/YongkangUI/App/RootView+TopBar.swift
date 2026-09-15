import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // MARK: - Top bar

    @ViewBuilder func topBar(for project: ProjectModel) -> some View {
        switch model.section {
        case .overview:
            TopBar(crumbs: [project.name], title: "Overview") {
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
            }
        case .board:
            let scoped = model.selection?.card(in: project.snapshot.cards)
            let demo = selectedBlock(in: project).flatMap { $0.isDemo ? $0 : nil }
            TopBar(
                crumbs: demo == nil ? [project.name] : [project.name, "Board"],
                title: scoped?.title ?? demo?.title ?? "Board"
            ) {
                if let demo {
                    NotebookStyle.pill(
                        demo.waiting ? "demo · waiting on you" : "approved",
                        demo.waiting ? Theme.amber : Theme.green, live: demo.waiting)
                }
                if let scoped, scoped.kind == .project { boardProgress(scoped, in: project) }
                completedToggle
                addMenu(for: project)
                Button {
                    go(to: project.startProductReview(agent: agent))
                } label: {
                    Label("Product review", systemImage: "sparkles")
                }
                .buttonStyle(.console)
            }
        case .agents:
            let watched = model.selectedAgent(in: project) ?? model.selectedSubagent(in: project)?.session
            TopBar(
                crumbs: [project.name],
                title: model.selection == .usage
                    ? "Usage"
                    : model.selectedSubagent(in: project)?.subagent.description
                        ?? watched?.title ?? model.selectedSession(in: project)?.title
                        ?? model.selectedMember(in: project)?.name ?? "Agents"
            ) {
                addMenu(for: project)
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
            }
        case .review:
            TopBar(crumbs: [project.repo.branch ?? project.name], title: "Review changes") {
                if let head = project.repo.head {
                    Text(head).font(Typo.mono(10.5)).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Button {
                    model.refreshChanges(force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.console)
            }
        case .blocks:
            TopBar(crumbs: [project.name], title: "Blocks") { completedToggle }
        }
    }

    private func boardProgress(_ card: NotebookCard, in project: ProjectModel) -> some View {
        let tasks = project.snapshot.cards.filter { $0.kind == .task && $0.project == card.id }
        let done = tasks.filter { $0.status == "done" }.count
        return HStack(spacing: 9) {
            MeterBar(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count))
                .frame(width: 96)
            Text("\(done)/\(tasks.count)").font(Typo.mono(11)).foregroundStyle(Theme.tx2)
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
                Button("Roadmap Entry…", systemImage: "map") { add(.roadmap, to: project) }
                Button("Project…", systemImage: "shippingbox") { add(.project, to: project) }
                Button("Task…", systemImage: "checkmark.circle") { add(.task, to: project) }
                Button("Memory…", systemImage: "brain") { add(.memory, to: project) }
                    .disabled(project.notebookProject(for: model.selection) == nil)
            }
            Divider()
            Button("Describe New Feature…", systemImage: "text.bubble") {
                go(to: project.startProduct("describe", agent: agent))
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
