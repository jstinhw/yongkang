import AppKit
import SwiftUI
import YongkangCore

/// One project as the sidebar draws it: the folder, and under it its running sessions (Agents)
/// or its tasks that are not idle (Board), in the order they want you.
package struct SidebarProject: Identifiable {
    package let project: Project
    /// Everything its agents have going, which its counts are made of: what a session that has
    /// exited left waiting on you still needs you, even with no row of its own.
    package let rows: [AgentRow]
    /// Its tasks that are not idle, which it lists under Board.
    let tasks: [AgentRow]
    /// How many memory entries its notebook holds, for the Memory row under Agents.
    let memory: Int

    /// `asking` is each session's terminal question, which only the window can see.
    package init(project: Project, summary: ChangeSummary, asking: [UUID: String] = [:]) {
        self.project = project
        rows = project.agentRows(summary: summary, asking: asking)
        tasks = project.taskRows(summary: summary)
        memory = project.cards.filter { $0.kind == .memory }.count
    }

    package var id: Project.ID { project.id }
    /// The rows it lists: one per running session.
    var sessions: [AgentRow] { rows.filter(\.isRunningSession) }
    var needsYou: Int { rows.filter { $0.state == .needsYou }.count }
    var toReview: Int { rows.filter { $0.state == .review }.count }
}

/// The column beside the rail: every open project at once, in every section, so what is waiting
/// on you in a project you are not looking at is always one glance away. Under Agents each lists
/// its running sessions and its Memory, and Usage — every project's — is pinned below them; under
/// Board each lists its tasks that are not idle. A project row opens that project in the current
/// section, and a row under it opens what it names there.
package struct ProjectSidebar: View {
    let section: ConsoleSection
    let projects: [SidebarProject]
    /// The project the selection lives in, and the selection itself.
    let entered: Project.ID?
    let selection: Route?
    /// Enters a project on a route, in a section.
    let open: (Project.ID, Route, ConsoleSection) -> Void
    /// The two ways a project arrives: described, or a folder that already exists.
    let create: () -> Void
    let add: () -> Void
    let closeSession: (Project.ID, CodeSession) -> Void
    let close: (Project.ID) -> Void
    /// Usage, which is every project's rather than one's.
    let openUsage: () -> Void

    /// Projects start open; this only remembers the ones the user folded.
    @State private var collapsed: Set<Project.ID> = []

    package init(
        section: ConsoleSection, projects: [SidebarProject], entered: Project.ID?, selection: Route?,
        open: @escaping (Project.ID, Route, ConsoleSection) -> Void,
        create: @escaping () -> Void, add: @escaping () -> Void,
        closeSession: @escaping (Project.ID, CodeSession) -> Void,
        close: @escaping (Project.ID) -> Void, openUsage: @escaping () -> Void
    ) {
        self.section = section
        self.projects = projects
        self.entered = entered
        self.selection = selection
        self.open = open
        self.create = create
        self.add = add
        self.closeSession = closeSession
        self.close = close
        self.openUsage = openUsage
    }

    package var body: some View {
        ListPane {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if projects.isEmpty {
                        Text("No projects yet")
                            .font(Typography.body).foregroundStyle(Theme.tx3)
                            .padding(.horizontal, 19).padding(.vertical, 8)
                    }
                    ForEach(projects) { item in
                        projectRow(item)
                        if !collapsed.contains(item.id) {
                            ForEach(section == .board ? item.tasks : item.sessions) { agentRow($0, in: item) }
                            if section == .agents {
                                pageRow(item, "Memory", icon: "brain", route: .memory(nil), count: item.memory)
                            }
                        }
                    }
                }
                .padding(.bottom, 14)
            }
            if section == .agents { usageRow }
            legend
        }
    }

    // MARK: - Header and legend

    private var header: some View {
        HStack(spacing: 8) {
            SectionLabel("Projects")
            Spacer(minLength: 0)
            Menu {
                Button("New Project…", action: create)
                Button("Open Folder…", action: add)
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tx2)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add a project")
            .accessibilityLabel("Add a project")
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
    }

    /// What the three colours mean, since they are the whole of what a row says at a glance. In
    /// a list dragged narrow the keys stack rather than break inside their words.
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { keys }
            VStack(alignment: .leading, spacing: 4) { keys }
        }
        .font(Typography.caption)
        .foregroundStyle(Theme.tx3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder private var keys: some View {
        key(Theme.amber, "needs you")
        key(Theme.green, "to review")
        key(Theme.accent, "working")
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .fixedSize()
    }

    // MARK: - Rows

    private func projectRow(_ item: SidebarProject) -> some View {
        let folded = collapsed.contains(item.id)
        return Button {
            open(item.id, page(for: section), section)
        } label: {
            HStack(spacing: 8) {
                Button {
                    if folded { collapsed.remove(item.id) } else { collapsed.insert(item.id) }
                } label: {
                    Image(systemName: folded ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.tx3)
                        .frame(width: 12)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    folded ? "Show \(item.project.name)’s agents" : "Hide \(item.project.name)’s agents")
                Text(item.project.name).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.needsYou > 0 { count(item.needsYou, Theme.amber, dot: true) }
                if item.toReview > 0 { count(item.toReview, Theme.green, dot: false) }
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowSelection(entered == item.id && !childSelected(in: item))
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .accessibilityLabel(summary(of: item))
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.project.directory])
            }
            Button("Close Project") { close(item.id) }
        }
    }

    /// A lit count: amber for what needs you, green for what waits for your review.
    private func count(_ number: Int, _ color: Color, dot: Bool) -> some View {
        HStack(spacing: 3) {
            if dot {
                Circle().fill(color).frame(width: 5, height: 5)
            } else {
                Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy))
            }
            Text("\(number)").font(Typography.monoCaption(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private func summary(of item: SidebarProject) -> String {
        var parts = [item.project.name]
        if item.needsYou > 0 { parts.append("\(item.needsYou) need you") }
        if item.toReview > 0 { parts.append("\(item.toReview) to review") }
        return parts.joined(separator: ", ")
    }

    /// A session under Agents, named after itself; a task under Board, named after itself and
    /// saying who is on it. Either opens in the section it is listed in.
    private func agentRow(_ row: AgentRow, in item: SidebarProject) -> some View {
        let isTask = !row.isRunningSession
        return Button {
            open(item.id, row.route, section)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                AgentStateGlyph(state: row.state).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isTask ? row.title : row.name).font(Typography.body).foregroundStyle(Theme.tx)
                        .lineLimit(1)
                    Text(isTask ? row.byLine : row.line).font(Typography.caption)
                        .foregroundStyle(row.state == .working ? Theme.tx3 : row.state.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 26)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .rowSelection(entered == item.id && isSelected(row))
        .padding(.horizontal, 8)
        .padding(.top, 1)
        .contextMenu {
            if !isTask, let session = row.session {
                Button("Close Session") { closeSession(item.id, session) }
            }
        }
    }

    /// Usage, pinned under every project's list: it is all of theirs.
    private var usageRow: some View {
        Button(action: openUsage) {
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 11))
                    .foregroundStyle(Theme.tx3).frame(width: 12)
                Text("Usage").font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                Spacer(minLength: 0)
                Text("all projects").font(Typography.caption).foregroundStyle(Theme.tx3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowSelection(selection == .usage)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    /// A page of the project's own under Agents, after its sessions: its memory, its usage.
    private func pageRow(
        _ item: SidebarProject, _ title: String, icon: String, route: Route, count: Int? = nil
    ) -> some View {
        Button {
            open(item.id, route, .agents)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Theme.tx3)
                    .frame(width: 12)
                Text(title).font(Typography.body).foregroundStyle(Theme.tx2)
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(Typography.mono).foregroundStyle(Theme.tx3) }
            }
            .padding(.leading, 26)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .rowSelection(entered == item.id && isPage(route))
        .padding(.horizontal, 8)
        .padding(.top, 1)
    }

    // MARK: - Selection

    /// The page a project row opens in each section.
    private func page(for section: ConsoleSection) -> Route {
        switch section {
        case .board: return .board
        case .agents: return .agents
        }
    }

    /// Whether the selection is on that page: any entry of Memory is Memory.
    private func isPage(_ route: Route) -> Bool {
        if case .memory = route, case .memory? = selection { return true }
        return selection == route
    }

    /// A session row stands for everything under that session: its terminal and transcript, a
    /// subagent it spawned, the block it is waiting on, and the reviews of the tasks it holds. A
    /// task row stands for its page and whatever it opens on.
    private func isSelected(_ row: AgentRow) -> Bool {
        guard row.isRunningSession, let session = row.session else {
            return selection == row.route || (row.task.map { selection == .task($0) } ?? false)
        }
        switch selection {
        case .session(session.id, _)?, .subagent(session.id, _)?: return true
        case .block(let id)?: return row.block?.id == id
        case .reviewTask(let task)?: return session.taskIDs.contains(task)
        default: return false
        }
    }

    private func childSelected(in item: SidebarProject) -> Bool {
        (section == .agents && isPage(.memory(nil)))
            || (section == .board ? item.tasks : item.sessions).contains(where: isSelected)
    }
}
