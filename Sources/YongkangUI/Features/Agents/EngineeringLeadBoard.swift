import SwiftUI
import YongkangCore

/// An assigned session's work, one lane per task: the report the agent filed for it and the
/// subagents it started, kept beside the live transcript after they return.
package struct EngineeringLeadBoard: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let blocks: [UserBlock]
    let openTask: (String) -> Void
    let openSubagent: (SubagentStatus) -> Void
    let openBlock: (UserBlock) -> Void

    package init(
        session: CodeSession,
        cards: [NotebookCard],
        blocks: [UserBlock],
        openTask: @escaping (String) -> Void,
        openSubagent: @escaping (SubagentStatus) -> Void,
        openBlock: @escaping (UserBlock) -> Void
    ) {
        self.session = session
        self.cards = cards
        self.blocks = blocks
        self.openTask = openTask
        self.openSubagent = openSubagent
        self.openBlock = openBlock
    }

    private var workers: [LeadWork] { session.coordination?.workers ?? [] }
    private var taskIDs: [String] {
        session.taskIDs + Set(workers.map(\.taskID)).subtracting(session.taskIDs).sorted()
    }
    private var unlinked: [SubagentStatus] {
        session.subagents.filter { agent in
            !taskIDs.contains(agent.taskID ?? "")
                && !workers.contains { $0.subagent(in: session)?.id == agent.id }
        }
    }

    package var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        plan
                        if geometry.size.width < 950 {
                            DisclosureGroup("Progress") {
                                LeadInspector(
                                    session: session, cards: cards, blocks: blocks,
                                    openTask: openTask, openBlock: openBlock, inline: true)
                            }
                            .font(Typography.body).tint(Theme.tx2).cardSurface()
                        }
                        ForEach(taskIDs, id: \.self) { lane($0) }
                        if !unlinked.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("Other subagents", trailing: "\(unlinked.count)")
                                ForEach(unlinked) { legacyWorker($0) }
                            }
                            .cardSurface()
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if geometry.size.width >= 950 {
                    LeadInspector(
                        session: session, cards: cards, blocks: blocks,
                        openTask: openTask, openBlock: openBlock)
                }
            }
        }
        .background(Theme.bg)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title).font(Typography.title).foregroundStyle(Theme.tx)
                Spacer(minLength: 8)
                if let updated = workers.compactMap(\.updatedAt).max() {
                    Text("Updated \(AgentUsage.ago(updated))").font(Typography.mono).foregroundStyle(Theme.tx3)
                }
            }
            Text(
                session.coordination?.strategy.nonEmpty
                    ?? "Each task's report lands in its lane as the agent files it, beside the subagents it started."
            )
            .font(Typography.body).foregroundStyle(Theme.tx2).fixedSize(horizontal: false, vertical: true)
            if !taskIDs.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { planMetrics }
                    VStack(alignment: .leading, spacing: 9) { planMetrics }
                }
            }
        }
        .cardSurface(padding: 16, border: Theme.accent.opacity(0.25))
    }

    @ViewBuilder private var planMetrics: some View {
        let done = taskIDs.filter { id in cards.contains { $0.id == id && $0.status == "done" } }.count
        summaryMetric("Agent", session.agent?.displayName ?? "—")
        summaryMetric("Tasks", "\(done) / \(taskIDs.count) done")
        summaryMetric("Subagents", "\(session.activeSubagents.count) running")
    }

    private func summaryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(Typography.section).tracking(1).foregroundStyle(Theme.tx3)
            Text(value).font(Typography.mono).foregroundStyle(Theme.tx)
        }
    }

    private func lane(_ taskID: String) -> some View {
        let card = cards.first { $0.kind == .task && $0.id == taskID }
        let assigned = workers.filter { $0.taskID == taskID }
        let remaining = session.subagents.filter { agent in
            agent.taskID == taskID && !assigned.contains { $0.subagent(in: session)?.id == agent.id }
        }
        let waiting = blocks.filter { $0.waiting && $0.task == taskID }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        openTask(taskID)
                    } label: {
                        Text(card?.title ?? taskID).font(Typography.headline).foregroundStyle(Theme.tx)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain).disabled(card == nil)
                    Text(taskID).font(Typography.mono).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 0)
                NotebookStyle.pill(
                    card?.status == "done"
                        ? "Done" : waiting.isEmpty ? card?.status.capitalized.nonEmpty ?? "Todo" : "Blocked",
                    card?.status == "done" ? Theme.green : waiting.isEmpty ? Theme.accent : Theme.amber)
            }
            if let dependencies = card?.dependsOn, !dependencies.isEmpty {
                dependencyLine(dependencies, prefix: "Task follows")
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            if assigned.isEmpty && remaining.isEmpty {
                Text(
                    card?.status == "done"
                        ? "Done. No report was filed." : "No report yet."
                )
                .font(Typography.body).foregroundStyle(Theme.tx3).padding(.vertical, 5)
            }
            ForEach(assigned) { worker($0) }
            ForEach(remaining) { legacyWorker($0) }
            ForEach(waiting) { block in
                Button {
                    openBlock(block)
                } label: {
                    Label(block.title, systemImage: "hand.raised.fill")
                        .font(Typography.body).foregroundStyle(Theme.amber)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.amber.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .cardSurface()
    }

    private func worker(_ work: LeadWork) -> some View {
        let agent = work.subagent(in: session)
        return HStack(alignment: .top, spacing: 10) {
            RoleTile(role: work.skill.nonEmpty ?? "work").padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(work.title.nonEmpty ?? work.id).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                        Text(work.id).font(Typography.mono).foregroundStyle(Theme.tx3)
                    }
                    Spacer(minLength: 0)
                    NotebookStyle.pill(
                        LeadDisplay.state(work), LeadDisplay.tint(work),
                        live: work.state == "running" && work.runtimeRunning != false)
                    if let agent {
                        Button {
                            openSubagent(agent)
                        } label: {
                            Image(systemName: "arrow.up.right").font(.system(size: 10))
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.tx2)
                        .accessibilityLabel("Open \(work.title) transcript")
                        .help("Open \(agent.displayName)’s transcript")
                    }
                }
                if !work.dependsOn.isEmpty { dependencyLine(work.dependsOn, prefix: "After") }
                Text(
                    "\(LeadDisplay.tokens(work.usedTokens)) tokens · \(LeadDisplay.minutes(work.elapsedMinutes())) elapsed"
                        + ((work.measuredModel ?? work.model.nonEmpty).map { " · \($0)" } ?? "")
                )
                .font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                .fixedSize(horizontal: false, vertical: true)
                if !work.report.isEmpty {
                    Label(work.report, systemImage: "arrow.turn.down.left")
                        .font(Typography.caption).foregroundStyle(Theme.tx2).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func dependencyLine(_ ids: [String], prefix: String) -> some View {
        Text("\(prefix): \(ids.joined(separator: ", "))")
            .font(Typography.mono).foregroundStyle(Theme.amber)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func legacyWorker(_ agent: SubagentStatus) -> some View {
        Button {
            openSubagent(agent)
        } label: {
            HStack(spacing: 10) {
                RoleTile(role: agent.agentType)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                    Text(agent.description).font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(2)
                    Text("No report filed for it").font(Typography.caption).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 0)
                NotebookStyle.pill(
                    agent.running ? "Running" : "Returned",
                    agent.running ? Theme.accent : Theme.violet, live: agent.running)
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Theme.tx3)
            }
            .contentShape(Rectangle()).padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }
}

/// Shared by the flow and transcript; it scrolls independently when a batch gets long.
struct LeadInspector: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let blocks: [UserBlock]
    let openTask: (String) -> Void
    let openBlock: (UserBlock) -> Void
    var inline = false

    var body: some View {
        if inline {
            content.padding(.top, 12)
        } else {
            ScrollView { content.padding(18) }
                .frame(width: Theme.inspectorWidth)
                .background(Theme.panel)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        }
    }

    private var content: some View {
        let done = session.taskIDs.filter { id in cards.contains { $0.id == id && $0.status == "done" } }.count
        let waiting = blocks.filter { $0.waiting && session.taskIDs.contains($0.task ?? "") }
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Progress")
                Text("\(done) / \(session.taskIDs.count) tasks done").font(Typography.headline)
                    .foregroundStyle(Theme.tx)
                MeterBar(
                    value: session.taskIDs.isEmpty ? 0 : Double(done) / Double(session.taskIDs.count), tint: Theme.green
                )
                Text("A task is done when the agent has checked its Done when. You review and commit it.")
                    .font(Typography.caption).foregroundStyle(Theme.tx3).fixedSize(horizontal: false, vertical: true)
            }
            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Needs attention", trailing: "\(waiting.count)")
                    ForEach(waiting) { block in
                        Button {
                            openBlock(block)
                        } label: {
                            Label(block.title, systemImage: "hand.raised")
                                .font(Typography.body).foregroundStyle(Theme.amber)
                                .multilineTextAlignment(.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !session.taskIDs.isEmpty {
                DisclosureGroup("Assigned tasks") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(session.taskIDs, id: \.self) { id in
                            Button {
                                openTask(id)
                            } label: {
                                Text(cards.first { $0.id == id }?.title ?? id)
                                    .font(Typography.caption).foregroundStyle(Theme.tx2)
                                    .multilineTextAlignment(.leading)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top, 8)
                }.font(Typography.body).tint(Theme.tx3).foregroundStyle(Theme.tx2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum LeadDisplay {
    static func tokens(_ value: Int?) -> String { value.map(AgentUsage.short) ?? "—" }
    static func minutes(_ value: Double?) -> String {
        value.map { String(format: $0 < 1 ? "%.1fm" : "%.0fm", $0) } ?? "—"
    }
    static func state(_ work: LeadWork) -> String {
        if work.state == "running", work.runtimeRunning == false { return "Awaiting update" }
        switch work.state {
        case "done": return "Done"
        case "review": return "In review"
        default: return work.state.capitalized
        }
    }
    static func tint(_ work: LeadWork) -> Color {
        if work.state == "running", work.runtimeRunning == false { return Theme.violet }
        switch work.state {
        case "running": return Theme.accent
        case "blocked": return Theme.amber
        case "failed": return Theme.red
        case "done": return Theme.green
        case "review": return Theme.violet
        default: return Theme.tx3
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
