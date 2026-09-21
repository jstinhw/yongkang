import AppKit
import SwiftUI
import YongkangCore

/// One agent: what it is on and where it has got to, its terminal or its transcript, and beside
/// them what it is waiting on you for, the task's Done when, what it can reach and what it spawned.
/// Whichever pane is showing, the header and the column beside it stay put.
package struct AgentPage<Content: View>: View {
    let session: CodeSession
    let project: Project
    let summary: ChangeSummary
    /// How the sidebar lists it, for its state and what it is doing. Nil once it has exited.
    let row: AgentRow?
    let pane: AgentPane
    /// The question on its screen, when there is one.
    let asking: String?
    /// Where its transcript is on disk.
    let source: URL?
    let select: (AgentPane) -> Void
    /// A block, a task's review, a subagent or the task itself.
    let open: (Route) -> Void
    let stop: () -> Void
    @ViewBuilder let content: Content

    package init(
        session: CodeSession, project: Project, summary: ChangeSummary, row: AgentRow?, pane: AgentPane,
        asking: String?, source: URL?, select: @escaping (AgentPane) -> Void, open: @escaping (Route) -> Void,
        stop: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) {
        self.session = session
        self.project = project
        self.summary = summary
        self.row = row
        self.pane = pane
        self.asking = asking
        self.source = source
        self.select = select
        self.open = open
        self.stop = stop
        self.content = content()
    }

    package var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.bg)
            AgentInspector(
                session: session, project: project, summary: summary, task: task, asking: asking,
                source: source, showTerminal: pane == .session ? nil : { select(.session) }, open: open, stop: stop)
        }
    }

    /// The task it is on: the row's, or the first of its chain.
    private var task: NotebookCard? {
        (row?.task ?? session.taskIDs.first).flatMap { id in project.cards.first { $0.id == id } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let row { AgentStateGlyph(state: row.state, size: 11) }
                    Text(status).font(Typography.caption(.semibold)).foregroundStyle(row?.state.color ?? Theme.tx3)
                }
                Text(session.title).font(Typography.title).foregroundStyle(Theme.tx)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    NotebookStyle.chip(project.name, mono: true)
                    if let task {
                        NotebookStyle.chip(task.id, mono: true)
                        Text("on \(task.title)").font(Typography.caption).foregroundStyle(Theme.tx3)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 12)
            Picker("Show", selection: Binding(get: { pane }, set: { select($0) })) {
                Text("Terminal").tag(AgentPane.session)
                Text("Transcript").tag(AgentPane.transcript)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var status: String {
        guard let row else { return session.exited ? "exited" : "idle" }
        return row.doing
    }
}

/// The column beside an agent: what it is waiting on you for first, then how far its task has
/// got, the folders it can reach, and the agents it spawned.
struct AgentInspector: View {
    let session: CodeSession
    let project: Project
    let summary: ChangeSummary
    let task: NotebookCard?
    let asking: String?
    let source: URL?
    /// Back to the terminal, where a question is answered. Nil while the terminal is showing.
    let showTerminal: (() -> Void)?
    let open: (Route) -> Void
    let stop: () -> Void

    /// Everything it raised that is still open: gates and demos on its tasks, and its proposals.
    private var blocks: [UserBlock] {
        project.blocks.waitingOnUser.filter { block in
            block.session == session.id || (block.session == nil && session.taskIDs.contains(block.task ?? ""))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if asking != nil || !blocks.isEmpty { waitingOnYou }
                    let waiting = summary.waiting(for: session)
                    if !waiting.isEmpty { forReview(waiting) }
                    if let task { doneWhen(task) }
                    access
                    if !session.subagents.isEmpty { subagents }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button {
                    if let source { NSWorkspace.shared.activateFileViewerSelecting([source]) }
                } label: {
                    Label("Transcript", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.console)
                .disabled(source == nil)
                .help("Reveal the transcript in Finder")
                Button(action: stop) {
                    Label("Stop Agent", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.console)
                .disabled(session.exited)
            }
            .padding(18)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .frame(width: Theme.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private var waitingOnYou: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Waiting on you")
            if let asking {
                VStack(alignment: .leading, spacing: 6) {
                    Label(asking, systemImage: "questionmark.bubble")
                        .font(Typography.body).foregroundStyle(Theme.amber)
                    if let showTerminal {
                        Button("Answer in the Terminal", action: showTerminal).buttonStyle(.consolePrimary)
                    } else {
                        Text("Answer it in the terminal.").font(Typography.caption).foregroundStyle(Theme.tx3)
                    }
                }
            }
            ForEach(blocks) { block in
                Button {
                    open(.block(block.id))
                } label: {
                    Label(block.title, systemImage: block.isDemo ? "rectangle.on.rectangle" : "hand.raised")
                        .font(Typography.body).foregroundStyle(Theme.amber)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func forReview(_ tasks: [SummaryTask]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Waiting for your review", trailing: "\(tasks.count)")
            ForEach(tasks) { task in
                Button {
                    open(.reviewTask(task.id))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.green)
                        Text(task.title).font(Typography.body).foregroundStyle(Theme.tx).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("+\(task.added) −\(task.removed)").font(Typography.mono).foregroundStyle(Theme.tx3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func doneWhen(_ task: NotebookCard) -> some View {
        let checks = NotebookIndex.checklist(in: task.body)
        let place = session.taskIDs.firstIndex(of: task.id).map { $0 + 1 }
        return VStack(alignment: .leading, spacing: 9) {
            SectionLabel(
                "Done when", trailing: checks.isEmpty ? nil : "\(checks.filter(\.done).count) / \(checks.count)")
            Button {
                open(.task(task.id))
            } label: {
                Text(task.title).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            if let place, session.taskIDs.count > 1 {
                Text("Task \(place) of \(session.taskIDs.count) in its chain")
                    .font(Typography.caption).foregroundStyle(Theme.tx3)
            }
            if checks.isEmpty {
                Text("Its page has no Done when list.").font(Typography.caption).foregroundStyle(Theme.tx3)
            }
            ForEach(Array(checks.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(item.done ? Theme.green : Theme.tx4)
                        .padding(.top, 2)
                    Text(item.text).font(Typography.body).foregroundStyle(Theme.prose)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The folder it works in, and any it was given to read beside it.
    private var access: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Access", trailing: "\(session.reading.count + 1) folder\(session.reading.isEmpty ? "" : "s")")
            VStack(spacing: 0) {
                folder(project.directory, "edits", Theme.accent)
                ForEach(session.reading, id: \.self) { url in
                    Rectangle().fill(Theme.line).frame(height: 1)
                    folder(url, "reads", Theme.tx2)
                }
            }
            .cardSurface(radius: 10, padding: 0)
            Text(
                session.reading.isEmpty
                    ? "Given no other folders when it started."
                    : "It changes \(project.name) only. Approving in Review commits there."
            )
            .font(Typography.caption).foregroundStyle(Theme.tx3)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func folder(_ url: URL, _ mode: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.tx3)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                Text(url.path).font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 4)
            Text(mode).font(Typography.caption(.semibold)).foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var subagents: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Subagents", trailing: "\(session.activeSubagents.count) running")
            ForEach(session.subagents.sorted { $0.running && !$1.running }) { subagent in
                Button {
                    open(.subagent(session: session.id, id: subagent.id))
                } label: {
                    HStack(spacing: 9) {
                        RoleTile(role: subagent.agentType, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(subagent.displayName).font(Typography.body).foregroundStyle(Theme.tx).lineLimit(1)
                            Text(subagent.description).font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        StateDot(color: subagent.running ? Theme.accent : Theme.green, live: subagent.running)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
