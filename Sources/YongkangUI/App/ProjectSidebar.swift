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
    /// Each session's finished tasks waiting for your review, listed under its row.
    let reviews: [UUID: [SummaryTask]]
    /// The sessions that have drawn a page (`NotebookFormat.page(of:in:)`), listed under their row.
    let pages: Set<UUID>
    /// Its folder was renamed, moved or deleted since it was opened. See `ProjectModel.missing`.
    let missing: Bool

    /// `asking` is each session's terminal question, which only the window can see.
    package init(project: Project, summary: ChangeSummary, asking: [UUID: String] = [:], missing: Bool = false) {
        self.project = project
        self.missing = missing
        rows = project.agentRows(summary: summary, asking: asking)
        tasks = project.taskRows(summary: summary)
        memory = project.cards.filter { $0.kind == .memory }.count
        reviews = Dictionary(
            uniqueKeysWithValues: project.sessions.map { ($0.id, summary.waiting(for: $0)) }.filter { !$0.1.isEmpty })
        pages = Set(
            project.sessions.map(\.id).filter {
                FileManager.default.fileExists(atPath: NotebookFormat.page(of: $0, in: project.notebookRoot).path)
            })
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
    /// Opens a plain shell in the project's folder, under Agents.
    let newTerminal: (Project.ID) -> Void
    let closeSession: (Project.ID, CodeSession) -> Void
    let close: (Project.ID) -> Void
    /// Usage, which is every project's rather than one's.
    let openUsage: () -> Void
    /// Moves a dragged project into the gap before the project at this index. There is one list
    /// for every section, so an order set under Board is the order Agents lists them in too.
    let move: (Project.ID, Int) -> Void

    /// Projects start open; this only remembers the ones the user folded.
    @State private var collapsed: Set<Project.ID> = []
    /// Which gap the insertion line is in while a project is dragged. A `LazyVStack` draws no
    /// line of its own — that comes with `List`'s `.onMove`, and a `List` here would bring its
    /// own chrome — so the gaps are drop targets and this says which one is lit.
    @State private var insertion: Int?

    package init(
        section: ConsoleSection, projects: [SidebarProject], entered: Project.ID?, selection: Route?,
        open: @escaping (Project.ID, Route, ConsoleSection) -> Void,
        create: @escaping () -> Void, add: @escaping () -> Void,
        newTerminal: @escaping (Project.ID) -> Void,
        closeSession: @escaping (Project.ID, CodeSession) -> Void,
        close: @escaping (Project.ID) -> Void, openUsage: @escaping () -> Void,
        move: @escaping (Project.ID, Int) -> Void
    ) {
        self.section = section
        self.projects = projects
        self.entered = entered
        self.selection = selection
        self.open = open
        self.create = create
        self.add = add
        self.newTerminal = newTerminal
        self.closeSession = closeSession
        self.close = close
        self.openUsage = openUsage
        self.move = move
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
                            ForEach(section == .board ? item.tasks : item.sessions) { row in
                                agentRow(row, in: item)
                                if section == .agents, let session = row.session {
                                    if item.pages.contains(session.id) { sessionPageRow(session, in: item) }
                                    ForEach(item.reviews[session.id] ?? []) { reviewRow($0, in: item) }
                                }
                            }
                            if section == .agents {
                                pageRow(item, "Memory", icon: "brain", route: .memory(nil), count: item.memory)
                                newTerminalRow(item)
                            }
                        }
                    }
                    if !projects.isEmpty { endGap }
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
                // The same two names as the File menu and the empty screen. Both name a project:
                // under a + beside Projects, "Open Folder…" reads as if it opened a folder inside
                // one. Nothing is copied, so it is Open, not Import.
                Button("New Project…", action: create)
                Button("Open Project…", action: add)
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

    /// The gap past the last project, without which a project could be dragged anywhere but
    /// to the end of the list.
    private var endGap: some View {
        Color.clear.frame(height: 18)
            .contentShape(Rectangle())
            .dropTarget(before: projects.count, line: $insertion, move: move)
    }

    private func projectRow(_ item: SidebarProject) -> some View {
        let folded = collapsed.contains(item.id)
        let index = projects.firstIndex { $0.id == item.id } ?? 0
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.project.name).font(Typography.body(.semibold))
                        .foregroundStyle(item.missing ? Theme.tx3 : Theme.tx)
                        .lineLimit(1)
                    if item.missing {
                        Text("Can’t find this project").font(Typography.caption).foregroundStyle(Theme.amber)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if item.missing {
                    Button("Remove") { close(item.id) }
                        .buttonStyle(.borderless)
                        .font(Typography.caption)
                        .help("Remove \(item.project.name) from Yongkang. Nothing on disk is touched.")
                }
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
        // The id, not the path: a project is only ever dragged within this list, and the
        // window looks it up by id anyway.
        .draggable(item.id.uuidString)
        .dropTarget(before: index, line: $insertion, move: move)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.project.directory])
            }
            .disabled(item.missing)
            Button(item.missing ? "Remove Project" : "Close Project") { close(item.id) }
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
        if item.missing { parts.append("project not found") }
        if item.needsYou > 0 { parts.append("\(item.needsYou) need you") }
        if item.toReview > 0 { parts.append("\(item.toReview) to review") }
        return parts.joined(separator: ", ")
    }

    /// A session under Agents, named after its task and saying which agent runs it; a task under
    /// Board, named after itself and saying who is on it. Either opens in the section it is listed in.
    private func agentRow(_ row: AgentRow, in item: SidebarProject) -> some View {
        let isTask = !row.isRunningSession
        return Button {
            open(item.id, row.route, section)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                // A plain shell has no state to show: its icon is what tells it from an agent.
                if row.session?.isTerminal == true {
                    Image(systemName: CodeSession.terminalIcon).font(.system(size: 10))
                        .foregroundStyle(Theme.tx2).frame(width: 12).padding(.top, 2)
                } else {
                    AgentStateGlyph(state: row.state).padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isTask ? row.title : row.label).font(Typography.body).foregroundStyle(Theme.tx)
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

    /// The page a session drew for you — its report, or Setup's and Product's plan — under it.
    private func sessionPageRow(_ session: CodeSession, in item: SidebarProject) -> some View {
        let route = Route.session(session.id, pane: .page)
        return Button {
            open(item.id, route, .agents)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc.richtext").font(.system(size: 10)).foregroundStyle(Theme.accent)
                Text("Page").font(Typography.caption).foregroundStyle(Theme.tx2).lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.leading, 44)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .rowSelection(entered == item.id && selection == route)
        .padding(.horizontal, 8)
        .padding(.top, 1)
        .help("The page \(session.title) drew")
    }

    /// A finished task waiting for your review, under the session that did it. Opens its review.
    private func reviewRow(_ task: SummaryTask, in item: SidebarProject) -> some View {
        Button {
            open(item.id, .reviewTask(task.id), .agents)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle").font(.system(size: 10)).foregroundStyle(Theme.green)
                Text(task.title).font(Typography.caption).foregroundStyle(Theme.tx2).lineLimit(1)
                Spacer(minLength: 4)
                Text("+\(task.added) −\(task.removed)").font(Typography.monoCaption).foregroundStyle(Theme.tx3)
            }
            .padding(.leading, 44)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .rowSelection(entered == item.id && selection == .reviewTask(task.id))
        .padding(.horizontal, 8)
        .padding(.top, 1)
        .help("Review \(task.title)")
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

    /// Opens a plain shell in the project's folder. Last under the project, below Memory, so it
    /// reads as an action rather than one of the rows it adds.
    private func newTerminalRow(_ item: SidebarProject) -> some View {
        Button {
            newTerminal(item.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tx3)
                    .frame(width: 12)
                Text("New Terminal").font(Typography.body).foregroundStyle(Theme.tx3)
                Spacer(minLength: 0)
            }
            .padding(.leading, 26)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.missing)
        .padding(.horizontal, 8)
        .padding(.top, 1)
        .help("Open a shell in \(item.project.name)’s folder")
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

    /// A session row stands for everything under that session: its terminal, a subagent it
    /// spawned, and the block it is waiting on — its page and its reviews are rows of their own.
    /// A task row stands for its page and whatever it opens on.
    private func isSelected(_ row: AgentRow) -> Bool {
        guard row.isRunningSession, let session = row.session else {
            return selection == row.route || (row.task.map { selection == .task($0) } ?? false)
        }
        switch selection {
        case .session(session.id, .session)?, .subagent(session.id, _)?: return true
        case .block(let id)?: return row.block?.id == id
        default: return false
        }
    }

    private func isReview(in item: SidebarProject) -> Bool {
        switch selection {
        case .reviewTask(let id)?: return item.reviews.values.contains { $0.contains { $0.id == id } }
        case .session(let id, .page)?: return item.pages.contains(id)
        default: return false
        }
    }

    private func childSelected(in item: SidebarProject) -> Bool {
        (section == .agents && (isPage(.memory(nil)) || isReview(in: item)))
            || (section == .board ? item.tasks : item.sessions).contains(where: isSelected)
    }
}

extension View {
    /// Makes the gap above this row a place a dragged project lands: the insertion line while a
    /// drag is over it, and the move when it is dropped. Only the line moves — a row never lights
    /// up, because a project highlighted under the cursor reads as somewhere to drop the drag
    /// *into*, and nothing here goes inside a project.
    fileprivate func dropTarget(
        before index: Int, line: Binding<Int?>, move: @escaping (Project.ID, Int) -> Void
    ) -> some View {
        overlay(alignment: .top) {
            Rectangle().fill(Theme.accent)
                .frame(height: 2)
                .padding(.horizontal, 8)
                .offset(y: 3)
                .opacity(line.wrappedValue == index ? 1 : 0)
        }
        .dropDestination(for: String.self) { dropped, _ in
            line.wrappedValue = nil
            guard let dragged = dropped.first.flatMap(UUID.init(uuidString:)) else { return false }
            move(dragged, index)
            return true
        } isTargeted: { over in
            if over {
                line.wrappedValue = index
            } else if line.wrappedValue == index {
                line.wrappedValue = nil
            }
        }
    }
}
