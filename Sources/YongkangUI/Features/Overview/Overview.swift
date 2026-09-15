import SwiftUI
import YongkangCore

/// What the project is doing right now, in one screen: who is working, what is waiting on
/// you, what changed on disk, and how far the work has got. Everything here is read from
/// the notebook, the transcripts and git — the app keeps no state of its own to drift.
package struct Overview: View {
    let project: Project
    let changes: [FileChange]
    let head: String?
    let go: (ConsoleSection, Route) -> Void
    let assign: () -> Void

    /// Loaded on a change rather than per render: reading a handful of task files and
    /// transcript timestamps is cheap, doing it inside `body` at 60fps is not.
    @State private var checklists: [String: (done: Int, total: Int)] = [:]
    @State private var lastWrote: [String: Date] = [:]
    @State private var recent: [(card: NotebookCard, at: Date)] = []

    package init(
        project: Project,
        changes: [FileChange],
        head: String?,
        go: @escaping (ConsoleSection, Route) -> Void,
        assign: @escaping () -> Void
    ) {
        self.project = project
        self.changes = changes
        self.head = head
        self.go = go
        self.assign = assign
    }

    private var workers: [(session: CodeSession, subagent: SubagentStatus)] {
        project.sessions.flatMap { session in session.activeSubagents.map { (session, $0) } }
    }

    package var body: some View {
        ScrollView {
            columns
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task(id: signature) { load() }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 20) {
                runningNow
                workingTree
                activity
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 20) {
                needsYou
                progress
                team
                Spacer(minLength: 0)
            }
            .frame(width: 332)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var signature: String {
        project.cards.map { "\($0.id):\($0.status)" }.joined()
            + workers.map(\.subagent.id).joined()
    }

    // MARK: - Running now

    private var runningNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Running now", trailing: workers.isEmpty ? nil : "dispatched by the lead")
            if workers.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz").foregroundStyle(Theme.tx4)
                    Text("No agents running. Pick tasks on the board and assign them.")
                        .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
                    Spacer(minLength: 0)
                    Button("Open the board") { go(.board, .board) }
                        .buttonStyle(.console)
                }
                .cardSurface()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
                    alignment: .leading, spacing: 12
                ) {
                    ForEach(workers, id: \.subagent.id) { worker in
                        workerCard(worker.session, worker.subagent)
                    }
                }
            }
        }
    }

    private func workerCard(_ session: CodeSession, _ subagent: SubagentStatus) -> some View {
        let task = subagent.taskID.flatMap { id in project.cards.first { $0.id == id } }
        let bars = subagent.taskID.flatMap { checklists[$0] }
        return Button {
            go(.agents, .subagent(session: session.id, id: subagent.id))
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    RoleTile(role: subagent.agentType, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subagent.displayName).font(Typo.display(12)).foregroundStyle(Theme.tx)
                            .lineLimit(1)
                        Text("\(subagent.agentType) · on \(task?.title ?? subagent.taskID ?? "no task")")
                            .font(Typo.text(10.5)).foregroundStyle(Theme.tx3).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    NotebookStyle.pill(wrote(subagent), Theme.accent, live: true)
                }
                if let bars {
                    VStack(alignment: .leading, spacing: 6) {
                        MeterBar(value: Double(bars.done) / Double(max(1, bars.total)))
                        Text("done when · \(bars.done) of \(bars.total) ticked")
                            .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A subagent has no clock of its own; its transcript's last write is when it last did
    /// anything, which is the honest version of "how long has this been going".
    private func wrote(_ subagent: SubagentStatus) -> String {
        guard let at = lastWrote[subagent.id] else { return "running" }
        return Overview.ago(at)
    }

    // MARK: - Working tree

    private var workingTree: some View {
        let added = changes.reduce(0) { $0 + $1.added }
        let removed = changes.reduce(0) { $0 + $1.removed }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Changes on disk", trailing: head)
            HStack(spacing: 14) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(changes.isEmpty ? Theme.tx4 : Theme.accent)
                if changes.isEmpty {
                    Text("Nothing changed since the last commit.")
                        .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
                } else {
                    Text("\(changes.count) file\(changes.count == 1 ? "" : "s") changed")
                        .font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                    Text("+\(added)").font(Typo.mono(11.5)).foregroundStyle(Theme.green)
                    Text("−\(removed)").font(Typo.mono(11.5)).foregroundStyle(Theme.red)
                }
                Spacer(minLength: 8)
                Button("Review changes") { go(.review, .review(file: nil)) }
                    .buttonStyle(.console)
                    .disabled(changes.isEmpty)
            }
            .cardSurface()
        }
    }

    // MARK: - Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Recent notebook writes")
            if recent.isEmpty {
                Text("The notebook is empty.").font(Typo.text(12)).foregroundStyle(Theme.tx4)
                    .padding(.vertical, 8)
            }
            ForEach(recent, id: \.card.id) { item in
                Button {
                    go(.board, route(for: item.card))
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Text(Overview.ago(item.at))
                            .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                            .frame(width: 46, alignment: .leading).padding(.top, 3)
                        StateDot(color: NotebookStyle.color(of: item.card.status)).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.card.title).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                                .lineLimit(1)
                            Text("\(item.card.kind.rawValue) · \(item.card.id)")
                                .font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if !item.card.status.isEmpty { NotebookStyle.pill(item.card.status) }
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func route(for card: NotebookCard) -> Route {
        switch card.kind {
        case .project: return .project(card.id)
        case .task: return .task(card.id)
        default: return .page(card.id)
        }
    }

    // MARK: - Needs you

    private var needsYou: some View {
        let waiting = project.blocks.filter(\.waiting)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Needs you")
                Spacer(minLength: 8)
                if !waiting.isEmpty { NotebookStyle.pill("\(waiting.count)", Theme.amber) }
            }
            if waiting.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal").foregroundStyle(Theme.green)
                    Text("Nothing waiting on you.").font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
                    Spacer(minLength: 0)
                }
                .cardSurface(padding: 13)
            }
            ForEach(waiting) { block in
                Button {
                    go(.blocks, .block(block.id))
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: block.isProposal ? "lightbulb" : "hand.raised")
                            .font(.system(size: 13))
                            .foregroundStyle(block.isProposal ? Theme.violet : Theme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.title).font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(
                                block.isProposal
                                    ? "product proposal"
                                    : "holds \(block.task ?? "an agent")"
                            )
                            .font(Typo.text(10.5)).foregroundStyle(Theme.tx3)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(
                        radius: 10, padding: 12, border: Color(hex: 0x222937),
                        fill: Color(hex: 0x151A22)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Progress

    private var progress: some View {
        let projects = project.cards.filter { $0.kind == .project }
        let tasks = project.cards.filter { $0.kind == .task }
        let done = tasks.filter { $0.status == "done" }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                NotebookStyle.statusRing(
                    tasks.isEmpty ? "todo" : "active",
                    progress: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count),
                    size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(done) of \(tasks.count) tasks done").font(Typo.display(15))
                    Text(
                        "\(workers.count) agent\(workers.count == 1 ? "" : "s") in flight · "
                            + "\(project.assignedTaskIDs.count) assigned"
                    )
                    .font(Typo.text(11)).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 0)
            }
            if !projects.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                ForEach(projects) { card in
                    let own = tasks.filter { $0.project == card.id }
                    let ownDone = own.filter { $0.status == "done" }.count
                    Button {
                        go(.board, .project(card.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(card.title).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(ownDone)/\(own.count)").font(Typo.mono(10.5))
                                    .foregroundStyle(Theme.tx3)
                            }
                            MeterBar(
                                value: own.isEmpty ? 0 : Double(ownDone) / Double(own.count),
                                tint: NotebookStyle.color(of: card.status))
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardSurface(padding: 16)
    }

    // MARK: - Team

    private var team: some View {
        // Keyed by who is running, not by the skill: two dispatches of Allen are Allen
        // twice over, and the skill is still what the tile beside the name is drawn from.
        let dispatched = Dictionary(grouping: workers.map(\.subagent), by: \.displayName)
        return VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Team").padding(.bottom, 6)
            ForEach(project.sessions.filter { $0.agent != nil }) { session in
                Button {
                    go(.agents, .session(session.id))
                } label: {
                    HStack(spacing: 9) {
                        RoleTile(role: session.isEngineeringLead ? "lead" : session.title)
                        Text(session.title).font(Typo.text(12)).foregroundStyle(Theme.tx2).lineLimit(1)
                        Spacer(minLength: 8)
                        StateDot(color: session.exited ? Theme.tx4 : Theme.accent, live: !session.exited)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(dispatched.keys.sorted(), id: \.self) { name in
                let running = dispatched[name] ?? []
                HStack(spacing: 9) {
                    RoleTile(role: running.first?.agentType ?? name)
                    Text(name).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                    Spacer(minLength: 8)
                    Text("\(running.count)").font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                    StateDot(color: Theme.accent, live: true)
                }
                .padding(.vertical, 5)
            }
        }
    }

    // MARK: - Loading

    private func load() {
        var lists: [String: (Int, Int)] = [:]
        for card in project.cards where card.kind == .task {
            let items = NotebookIndex.checklist(at: card.url)
            if !items.isEmpty { lists[card.id] = (items.filter(\.done).count, items.count) }
        }
        checklists = lists

        var wrote: [String: Date] = [:]
        for worker in workers {
            let values = try? worker.subagent.transcriptURL.resourceValues(forKeys: [.contentModificationDateKey])
            if let date = values?.contentModificationDate { wrote[worker.subagent.id] = date }
        }
        lastWrote = wrote

        recent = project.cards
            .filter { $0.kind != .run }
            .compactMap { card in
                let values = try? card.url.resourceValues(forKeys: [.contentModificationDateKey])
                return values?.contentModificationDate.map { (card, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map { (card: $0.0, at: $0.1) }
    }

    /// Short relative time — a feed of "4m" reads faster than one of full timestamps.
    static func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(max(seconds, 0))s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }
}
