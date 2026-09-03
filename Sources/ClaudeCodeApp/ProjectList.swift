import SwiftUI
import AppKit

/// The 268pt column: whatever the rail's current section is a list of. One column per
/// section rather than one tree holding everything at once — the old sidebar made you read
/// past the notebook to find the agent you were watching.
struct ProjectList: View {
    let section: ConsoleSection
    let project: Project
    @Binding var selection: String?
    let showDone: Bool
    /// Only read when the Review section is showing; empty everywhere else.
    let changes: [FileChange]
    let assign: ([NotebookCard]) -> Void
    let closeSession: (CodeSession) -> Void

    /// Agent trees start open; this only remembers the roots the user collapsed.
    @State private var collapsed: Set<UUID> = []
    @State private var previousSection: ConsoleSection?
    @State private var hiddenCompletedTasks: Set<String> = []

    var body: some View {
        ListPane {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .overview: overviewRows
                    case .board: boardRows
                    case .agents: agentRows
                    case .review: reviewRows
                    case .blocks: blockRows
                    case .terminals: terminalRows
                    }
                }
                .padding(.bottom, 14)
            }
            footer
        }
        .onChange(of: section) { next in
            if previousSection == .agents && next != .agents {
                hiddenCompletedTasks.formUnion(project.cards.filter { $0.kind == .task && $0.status == "done" }
                    .map(\.id))
            }
            previousSection = next
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack(spacing: 9) {
            Text("yk")
                .font(Typo.mono(10, .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).font(Typo.display(13.5)).foregroundStyle(Theme.tx)
                Text(project.directory.path)
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder private var footer: some View {
        if let note = footNote {
            Text(note)
                .font(Typo.mono(10))
                .foregroundStyle(Theme.tx3)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    private var footNote: String? {
        switch section {
        case .agents: return "Agents are named <task-id>-<role>, which is how a subagent is matched back to its task."
        case .blocks: return "A block is one file in .notebook/blocks/. Clearing it releases the agent waiting on it."
        case .review: return "Merging is yours. The lead stops at the PR."
        default: return nil
        }
    }

    // MARK: - Rows

    private func group(_ title: String, _ trailing: String? = nil) -> some View {
        SectionLabel(title, trailing: trailing)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func row<Content: View>(_ tag: String, @ViewBuilder content: () -> Content) -> some View {
        Button { selection = tag } label: {
            content()
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowSelection(selection == tag)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private func cardRow(_ card: NotebookCard, tag: String) -> some View {
        row(tag) {
            HStack(alignment: .top, spacing: 10) {
                NotebookStyle.statusRing(card.status, progress: progress(of: card), size: 14)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(Typo.text(12))
                        .foregroundStyle(selection == tag ? Theme.tx : Theme.tx2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(card.id).font(Typo.mono(9.5)).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Spacer(minLength: 0)
                if project.assignedTaskIDs.contains(card.id) && card.status != "done" {
                    NotebookStyle.pill("wip")
                }
            }
            .opacity(card.status == "done" ? 0.6 : 1)
        }
    }

    private func progress(of card: NotebookCard) -> Double {
        guard card.kind == .project else { return card.status == "active" ? 0.55 : 0 }
        let tasks = project.cards.filter { $0.kind == .task && $0.project == card.id }
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.filter { $0.status == "done" }.count) / Double(tasks.count)
    }

    // MARK: - Overview

    @ViewBuilder private var overviewRows: some View {
        let online = project.sessions.filter { $0.agent != nil && !$0.exited }
        group("Agents online", "\(online.reduce(0) { $0 + $1.activeSubagents.count } + online.count)")
        if online.isEmpty {
            empty("No agents running")
        } else {
            ForEach(online) { session in
                sessionRow(session)
                ForEach(session.activeSubagents) { subagent in
                    subagentRow(subagent, in: session)
                }
            }
        }
        group("Notebook")
        ForEach(NotebookKindCount.all(in: project.cards), id: \.label) { item in
            HStack(spacing: 9) {
                Image(systemName: item.icon).font(.system(size: 12)).foregroundStyle(Theme.tx3)
                Text(item.label).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                Spacer(minLength: 8)
                Text("\(item.count)").font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Board

    @ViewBuilder private var boardRows: some View {
        row(Tag.board(project)) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.split.3x1").font(.system(size: 12))
                    .foregroundStyle(selection == Tag.board(project) ? Theme.accent : Theme.tx3)
                Text("Board").font(Typo.text(12.5))
                    .foregroundStyle(selection == Tag.board(project) ? Theme.tx : Theme.tx2)
            }
        }
        let roadmaps = NotebookIndex.ordered(project.cards.filter { $0.kind == .roadmap })
        if !roadmaps.isEmpty {
            group("Roadmap", "\(roadmaps.count)")
            ForEach(roadmaps) { cardRow($0, tag: Tag.page($0.id)) }
        }
        let projects = visible(project.cards.filter { $0.kind == .project })
        group("Projects", "\(projects.count)")
        if projects.isEmpty { empty("No projects yet") }
        ForEach(projects) { cardRow($0, tag: Tag.project($0.id)) }
        if let scope = scopedProject {
            let tasks = visible(project.cards.filter { $0.kind == .task && $0.project == scope.id })
            group("Tasks in \(scope.title)", "\(tasks.count)")
            ForEach(tasks) { card in
                cardRow(card, tag: Tag.task(card.id))
                    .contextMenu {
                        Button("Assign to Engineering Lead") { assign([card]) }
                            .disabled(card.status == "done" || project.assignedTaskIDs.contains(card.id))
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([card.url])
                        }
                    }
            }
            let memory = project.cards.filter { $0.kind == .memory && $0.project == scope.id }
            if !memory.isEmpty {
                group("Memory", "\(memory.count)")
                ForEach(memory) { card in
                    row(Tag.page(card.id)) {
                        HStack(spacing: 9) {
                            Image(systemName: "brain").font(.system(size: 11)).foregroundStyle(Theme.tx3)
                            Text(card.title).font(Typo.text(12)).foregroundStyle(Theme.tx2).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// The project the board is scoped to: whatever is selected, or the project a selected
    /// task belongs to, so its tasks stay listed while you read one.
    private var scopedProject: NotebookCard? {
        if let id = Tag.scope(selection, "project") {
            return project.cards.first { $0.id == id && $0.kind == .project }
        }
        if let id = Tag.scope(selection, "task"),
           let task = project.cards.first(where: { $0.id == id }), let owner = task.project {
            return project.cards.first { $0.id == owner && $0.kind == .project }
        }
        return visible(project.cards.filter { $0.kind == .project }).first
    }

    private func visible(_ cards: [NotebookCard]) -> [NotebookCard] {
        NotebookIndex.ordered(showDone ? cards
            : cards.filter { $0.kind == .project ? !NotebookIndex.isFinished($0, in: project.cards)
                                                 : $0.status != "done" })
    }

    // MARK: - Agents

    @ViewBuilder private var agentRows: some View {
        let sessions = project.sessions.filter { $0.agent != nil }
        group("Sessions", "\(sessions.count)")
        if sessions.isEmpty { empty("No agents running") }
        ForEach(sessions) { session in
            sessionRow(session)
                .contextMenu { Button("Close Session") { closeSession(session) } }
            if !collapsed.contains(session.id) {
                ForEach(displayedSubagents(in: session)) { subagentRow($0, in: session) }
            }
        }
    }

    private func displayedSubagents(in session: CodeSession) -> [SubagentStatus] {
        session.subagents.filter { subagent in
            guard !subagent.running else { return true }
            guard let taskID = subagent.taskID else { return false }
            return !hiddenCompletedTasks.contains(taskID)
        }
    }

    private func sessionRow(_ session: CodeSession) -> some View {
        // Every agent row opens that agent's transcript; only a service terminal, which has
        // none, is its terminal. Picking a PTY is what the Terminals section is for.
        let tag = session.agent == nil ? Tag.session(session) : Tag.transcript(session.id)
        let running = session.activeSubagents.count
        return row(tag) {
            HStack(spacing: 9) {
                RoleTile(role: session.isEngineeringLead ? "lead" : session.title, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title).font(Typo.text(12, .medium))
                        .foregroundStyle(session.exited ? Theme.tx3 : Theme.tx)
                        .lineLimit(1)
                    Text(subtitle(of: session)).font(Typo.text(10.5)).foregroundStyle(Theme.tx3)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if !session.subagents.isEmpty {
                    Button { toggle(session) } label: {
                        Image(systemName: collapsed.contains(session.id) ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.tx3)
                    }
                    .buttonStyle(.borderless)
                }
                StateDot(color: session.exited ? Theme.tx4 : (running > 0 ? Theme.accent : Theme.green),
                         live: running > 0)
            }
        }
    }

    private func subtitle(of session: CodeSession) -> String {
        guard session.isEngineeringLead else {
            return session.exited ? "exited" : (session.agent?.displayName ?? "session")
        }
        let running = session.activeSubagents.count
        return "\(session.taskIDs.count) task\(session.taskIDs.count == 1 ? "" : "s") · \(running) running"
    }

    private func toggle(_ session: CodeSession) {
        if collapsed.contains(session.id) { collapsed.remove(session.id) }
        else { collapsed.insert(session.id) }
    }

    private func subagentRow(_ subagent: SubagentStatus, in session: CodeSession) -> some View {
        let tag = Tag.subagent(session, subagent)
        return HStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(width: 1).padding(.leading, 25)
            row(tag) {
                HStack(spacing: 8) {
                    RoleTile(role: subagent.agentType, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(subagent.description).font(Typo.mono(10.5))
                            .foregroundStyle(selection == tag ? Theme.tx : Theme.tx2)
                            .lineLimit(1).truncationMode(.middle)
                        Text(subagent.agentType).font(Typo.text(10)).foregroundStyle(Theme.tx3)
                    }
                    Spacer(minLength: 4)
                    StateDot(color: subagent.running ? Theme.accent : Theme.green, live: subagent.running)
                }
            }
        }
    }

    // MARK: - Review

    @ViewBuilder private var reviewRows: some View {
        let added = changes.reduce(0) { $0 + $1.added }
        let removed = changes.reduce(0) { $0 + $1.removed }
        group("Files", "+\(added) −\(removed)")
        if changes.isEmpty { empty("Nothing changed since HEAD") }
        ForEach(changes) { change in
            row(Tag.review(project) + ":" + change.path) {
                HStack(spacing: 9) {
                    Image(systemName: change.untracked ? "doc.badge.plus" : "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(change.untracked ? Theme.green : Theme.tx3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(change.name).font(Typo.mono(11)).foregroundStyle(Theme.tx).lineLimit(1)
                        Text(change.directory).font(Typo.mono(9.5)).foregroundStyle(Theme.tx3)
                            .lineLimit(1).truncationMode(.head)
                    }
                    Spacer(minLength: 6)
                    Text("+\(change.added)").font(Typo.mono(10)).foregroundStyle(Theme.green)
                    Text("−\(change.removed)").font(Typo.mono(10)).foregroundStyle(Theme.red)
                }
            }
        }
    }

    // MARK: - Blocks

    @ViewBuilder private var blockRows: some View {
        let waiting = project.blocks.filter(\.waiting)
        let resolved = project.blocks.filter { !$0.waiting }
        group("Waiting on you", "\(waiting.count)")
        if waiting.isEmpty { empty("Nothing waiting on you") }
        ForEach(waiting) { blockRow($0) }
        if !resolved.isEmpty {
            group("Resolved", "\(resolved.count)")
            ForEach(resolved) { blockRow($0).opacity(0.55) }
        }
    }

    private func blockRow(_ block: UserBlock) -> some View {
        row(Tag.block(block)) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: block.waiting
                      ? (block.isProposal ? "lightbulb" : "hand.raised") : "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(block.waiting ? (block.isProposal ? Theme.violet : Theme.amber)
                                                   : Theme.green)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title).font(Typo.text(12.5))
                        .foregroundStyle(selection == Tag.block(block) ? Theme.tx : Theme.tx2)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let task = block.task {
                        Text("holds \(task)").font(Typo.text(10.5)).foregroundStyle(Theme.tx3).lineLimit(1)
                    } else if block.isProposal {
                        Text("product proposal").font(Typo.text(10.5)).foregroundStyle(Theme.tx3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Terminals

    @ViewBuilder private var terminalRows: some View {
        group("Sessions", "\(project.sessions.count)")
        if project.sessions.isEmpty { empty("Nothing running") }
        ForEach(project.sessions) { session in
            row(Tag.session(session)) {
                HStack(spacing: 9) {
                    Image(systemName: session.icon).font(.system(size: 12))
                        .foregroundStyle(session.exited ? Theme.tx4 : Theme.tx2)
                    Text(session.title).font(Typo.text(12))
                        .foregroundStyle(session.exited ? Theme.tx3 : Theme.tx).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(session.exited ? "exited" : "live")
                        .font(Typo.mono(9.5)).foregroundStyle(Theme.tx3)
                }
            }
            .contextMenu { Button("Close Session") { closeSession(session) } }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(Typo.text(12))
            .foregroundStyle(Theme.tx4)
            .padding(.horizontal, 19)
            .padding(.vertical, 8)
    }
}

/// The notebook's shape in one line per kind — what the overview column counts.
struct NotebookKindCount {
    let label: String
    let icon: String
    let count: Int

    static func all(in cards: [NotebookCard]) -> [NotebookKindCount] {
        [NotebookKindCount(label: "Roadmap", icon: "map",
                           count: cards.filter { $0.kind == .roadmap }.count),
         NotebookKindCount(label: "Projects", icon: "shippingbox",
                           count: cards.filter { $0.kind == .project }.count),
         NotebookKindCount(label: "Tasks", icon: "checkmark.circle",
                           count: cards.filter { $0.kind == .task }.count),
         NotebookKindCount(label: "Memory", icon: "brain",
                           count: cards.filter { $0.kind == .memory }.count)]
    }
}

extension CodeSession {
    var isEngineeringLead: Bool { title.hasPrefix("Engineering Lead") }
}
