import SwiftUI
import YongkangCore

/// A project's running sessions side by side, in three columns: what needs you, what waits for
/// your review, what is at work. The same sessions the sidebar lists under the project, with room
/// to say what each one is on and to act on it without opening it first.
///
/// Sessions, not tasks: starting work on a task is the board's, and so is what a session that
/// has exited left waiting on you, which the header only counts.
package struct ProjectAgentsPage: View {
    let project: Project
    /// Everything the project's agents have going; the page draws the running sessions of it.
    let rows: [AgentRow]
    let summary: ChangeSummary
    let open: (Route) -> Void
    let openBoard: () -> Void
    let newAgent: () -> Void

    package init(
        project: Project, rows: [AgentRow], summary: ChangeSummary, open: @escaping (Route) -> Void,
        openBoard: @escaping () -> Void, newAgent: @escaping () -> Void
    ) {
        self.project = project
        self.rows = rows
        self.summary = summary
        self.open = open
        self.openBoard = openBoard
        self.newAgent = newAgent
    }

    private var sessions: [AgentRow] { rows.filter(\.isRunningSession) }

    package var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    ForEach([AgentRow.State.needsYou, .review, .working], id: \.self) { lane($0) }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
        .background(Theme.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name).font(Typography.title).foregroundStyle(Theme.tx)
                HStack(spacing: 12) {
                    Text(project.directory.path).font(Typography.mono).foregroundStyle(Theme.tx3)
                        .lineLimit(1).truncationMode(.head)
                    Text("\(sessions.count) running").font(Typography.caption).foregroundStyle(Theme.prose)
                    ForEach([AgentRow.State.needsYou, .review, .working], id: \.self) { state in
                        let count = sessions.filter { $0.state == state }.count
                        if count > 0 {
                            HStack(spacing: 5) {
                                Circle().fill(state.color).frame(width: 6, height: 6)
                                Text("\(count) \(state.title.lowercased())")
                            }
                            .font(Typography.caption).foregroundStyle(Theme.prose)
                        }
                    }
                }
                let elsewhere = rows.count - sessions.count
                if elsewhere > 0 {
                    Text(
                        "\(elsewhere) more \(elsewhere == 1 ? "thing waits" : "things wait") on you on the board."
                    )
                    .font(Typography.caption).foregroundStyle(Theme.tx3)
                }
            }
            Spacer(minLength: 12)
            Button("Open Board", action: openBoard).buttonStyle(.console)
            Button(action: newAgent) {
                Label("New Agent Here", systemImage: "plus")
            }
            .buttonStyle(.console)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    // MARK: - Columns

    private func lane(_ state: AgentRow.State) -> some View {
        let cards = sessions.filter { $0.state == state }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(state.color).frame(width: 7, height: 7)
                SectionLabel(state.title, trailing: "\(cards.count)")
            }
            if cards.isEmpty {
                Text(nothing(in: state)).font(Typography.caption).foregroundStyle(Theme.tx3)
                    .padding(.vertical, 6)
            }
            ForEach(cards) { card($0) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func nothing(in state: AgentRow.State) -> String {
        switch state {
        case .needsYou: return "No running agent is waiting on you."
        case .review: return "No running agent has work for your review."
        case .working: return "No agent is at work on this project."
        }
    }

    private func card(_ row: AgentRow) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                AgentStateGlyph(state: row.state, size: 11)
                Text(row.doing).font(Typography.caption(.semibold)).foregroundStyle(row.state.color)
            }
            Button {
                open(row.route)
            } label: {
                Text(row.label).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The work is the headline and the CLI running it is the note under it, the same
            // way round as the sidebar. "Run 2 ready" starts two sessions at once, and two
            // cards reading "Claude Code" and "Claude Code 2" say nothing about which is which.
            if row.task != nil {
                HStack(spacing: 6) {
                    RoleTile(role: row.agentName, size: 18)
                    Text(row.agentName).font(Typography.caption).foregroundStyle(Theme.tx2).lineLimit(1)
                }
            }
            if let detail = detail(of: row) {
                Text(detail).font(Typography.caption).foregroundStyle(Theme.prose)
                    .lineLimit(3).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.well))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.wellLine, lineWidth: 1))
            }
            footer(of: row)
        }
        .cardSurface(radius: 10, border: row.state == .needsYou ? Theme.amber.opacity(0.45) : Theme.line2)
    }

    /// What the card says in its well: the question, what is waiting for review, or what the
    /// work is.
    private func detail(of row: AgentRow) -> String? {
        switch row.state {
        case .needsYou:
            if let block = row.block { return NotebookIndex.brief(of: block.body) ?? block.title }
            return row.reason
        case .review:
            guard let task = reviewed(row) else { return nil }
            let checks = NotebookIndex.checklist(in: task.body)
            let checked = checks.isEmpty ? "" : "Checked \(checks.filter(\.done).count) of \(checks.count) · "
            return checked
                + "\(task.files.count) file\(task.files.count == 1 ? "" : "s") · +\(task.added) −\(task.removed)"
        case .working:
            if let session = row.session, !session.activeSubagents.isEmpty {
                let names = session.activeSubagents.map(\.displayName).joined(separator: ", ")
                return
                    "\(session.activeSubagents.count) subagent\(session.activeSubagents.count == 1 ? "" : "s") running: \(names)"
            }
            return row.task.flatMap { id in project.cards.first { $0.id == id } }.flatMap {
                NotebookIndex.brief(of: $0.body)
            }
        }
    }

    /// The task a review card is about: the one the row is, or the session's first waiting.
    private func reviewed(_ row: AgentRow) -> SummaryTask? {
        if case .reviewTask(let id) = row.route { return summary.tasks.first { $0.id == id } }
        return row.session.flatMap { summary.waiting(for: $0).first }
    }

    @ViewBuilder private func footer(of row: AgentRow) -> some View {
        switch row.state {
        case .needsYou:
            Button(action(for: row)) { open(row.block.map { .block($0.id) } ?? row.route) }
                .buttonStyle(.consolePrimary)
        case .review:
            HStack(spacing: 8) {
                Button("Review") { open(reviewed(row).map { .reviewTask($0.id) } ?? row.route) }
                    .buttonStyle(.console)
                Text("nothing committed yet").font(Typography.caption).foregroundStyle(Theme.tx3)
            }
        case .working:
            let checks =
                row.task.flatMap { id in project.cards.first { $0.id == id } }
                .map { NotebookIndex.checklist(in: $0.body) } ?? []
            if !checks.isEmpty {
                HStack(spacing: 8) {
                    Text("Done when \(checks.filter(\.done).count) / \(checks.count)")
                        .font(Typography.caption).foregroundStyle(Theme.tx2)
                    MeterBar(value: Double(checks.filter(\.done).count) / Double(checks.count))
                }
            }
        }
    }

    private func action(for row: AgentRow) -> String {
        guard let block = row.block else { return "Answer" }
        return block.isProposal ? "Open Proposal" : block.isDemo ? "See Demo" : "Open Block"
    }
}
