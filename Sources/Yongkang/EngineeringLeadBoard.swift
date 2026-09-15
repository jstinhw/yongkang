import SwiftUI

/// The recorded plan stays beside live transcripts, including workers that have returned.
struct EngineeringLeadBoard: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let blocks: [UserBlock]
    let team: [TeamMember]
    let openTask: (String) -> Void
    let openSubagent: (SubagentStatus) -> Void
    let openBlock: (UserBlock) -> Void

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

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        plan
                        if geometry.size.width < 950 {
                            DisclosureGroup("Check-ins & memory") {
                                LeadInspector(
                                    session: session, cards: cards, blocks: blocks,
                                    openTask: openTask, openBlock: openBlock, inline: true)
                            }
                            .font(Typo.text(12)).tint(Theme.tx2).cardSurface()
                        }
                        ForEach(taskIDs, id: \.self) { lane($0) }
                        if !unlinked.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("Other workers", trailing: "\(unlinked.count)")
                                ForEach(unlinked) { legacyWorker($0) }
                            }
                            .cardSurface()
                        }
                        roster
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
                Text(taskIDs.isEmpty ? "Ready for a task" : "Coordination plan")
                    .font(Typo.display(21)).foregroundStyle(Theme.tx)
                Spacer(minLength: 8)
                if let updated = session.coordination?.updatedAt {
                    Text("Updated \(AgentUsage.ago(updated))").font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                }
            }
            Text(
                session.coordination?.strategy.nonEmpty
                    ?? (taskIDs.isEmpty
                        ? "Assign tasks from the board. The lead will size the work, choose specialists and run independent subtasks together."
                        : "Waiting for the lead’s plan. Existing workers and their transcripts remain available below.")
            )
            .font(Typo.text(12)).foregroundStyle(Theme.tx2).fixedSize(horizontal: false, vertical: true)
            if !taskIDs.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { planMetrics }
                    VStack(alignment: .leading, spacing: 9) { planMetrics }
                }
                Divider().overlay(Theme.line)
                HStack(spacing: 7) {
                    ForEach(Array(["Plan", "Parallel work", "Report back", "QA", "Accept"].enumerated()), id: \.offset)
                    { index, label in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.tx3)
                        }
                        Text(label).font(Typo.mono(10)).foregroundStyle(index == 3 ? Theme.violet : Theme.tx2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardSurface(padding: 16, border: Theme.accent.opacity(0.25))
    }

    @ViewBuilder private var planMetrics: some View {
        summaryMetric("Scope", "\(taskIDs.count) tasks · \(workers.count) planned subtasks")
        summaryMetric(
            "Parallel",
            "\(session.activeSubagents.count) running"
                + (session.coordination?.parallelLimit.map { " / \($0) slots" } ?? ""))
        summaryMetric(
            "Estimate",
            "\(LeadDisplay.tokens(session.coordination?.estimatedTokens)) tokens · "
                + LeadDisplay.minutes(session.coordination?.estimatedMinutes))
    }

    private func summaryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(Typo.section).tracking(1).foregroundStyle(Theme.tx3)
            Text(value).font(Typo.mono(11)).foregroundStyle(Theme.tx)
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
                        Text(card?.title ?? taskID).font(Typo.display(14)).foregroundStyle(Theme.tx)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain).disabled(card == nil)
                    Text(taskID).font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 0)
                NotebookStyle.pill(
                    card?.status == "done"
                        ? "QA passed" : waiting.isEmpty ? card?.status.capitalized ?? "Planned" : "Blocked",
                    card?.status == "done" ? Theme.green : waiting.isEmpty ? Theme.accent : Theme.amber)
            }
            if let dependencies = card?.dependsOn, !dependencies.isEmpty {
                dependencyLine(dependencies, prefix: "Task follows")
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            if assigned.isEmpty && remaining.isEmpty {
                Text(
                    card?.status == "done"
                        ? "Accepted. No worker records available." : "Awaiting dispatch after dependencies clear."
                )
                .font(Typo.text(11.5)).foregroundStyle(Theme.tx3).padding(.vertical, 5)
            }
            ForEach(assigned) { worker($0) }
            ForEach(remaining) { legacyWorker($0) }
            ForEach(waiting) { block in
                Button {
                    openBlock(block)
                } label: {
                    Label(block.title, systemImage: "hand.raised.fill")
                        .font(Typo.text(11.5)).foregroundStyle(Theme.amber)
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
            RoleTile(role: work.skill).padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(work.title.nonEmpty ?? work.id).font(Typo.display(12)).foregroundStyle(Theme.tx)
                        Text(
                            "\(work.skill.nonEmpty ?? "Skill pending") · \(work.measuredModel ?? work.model.nonEmpty ?? "Model unreported")"
                        )
                        .font(Typo.mono(10)).foregroundStyle(Theme.tx2)
                        .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 12) {
                    Text(
                        "\(LeadDisplay.tokens(work.usedTokens)) \(work.usedTokens == nil ? "used" : work.tokenSource.lowercased()) / \(LeadDisplay.tokens(work.estimatedTokens)) est. tokens"
                    )
                    Text(
                        "\(LeadDisplay.minutes(work.elapsedMinutes())) elapsed / \(LeadDisplay.minutes(work.estimatedMinutes)) est."
                    )
                }
                .font(Typo.mono(9.5)).foregroundStyle(Theme.tx3)
                .fixedSize(horizontal: false, vertical: true)
                if !work.report.isEmpty {
                    Label(work.report, systemImage: "arrow.turn.down.left")
                        .font(Typo.text(11)).foregroundStyle(Theme.tx2).lineLimit(2)
                }
                DisclosureGroup(
                    "Why this assignment · check-in \(work.updatedAt.map { AgentUsage.ago($0) } ?? "unreported")"
                ) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(work.reason.nonEmpty ?? "Selection rationale not recorded.")
                        if !work.report.isEmpty { Text("Report: \(work.report)") }
                        Text("Worker ID: \(work.id)").font(Typo.mono(10))
                    }
                    .font(Typo.text(11)).foregroundStyle(Theme.tx2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                }
                .font(Typo.text(10.5)).foregroundStyle(Theme.tx3).tint(Theme.tx3)
            }
        }
        .padding(.vertical, 5)
    }

    private func dependencyLine(_ ids: [String], prefix: String) -> some View {
        Text("\(prefix): \(ids.joined(separator: ", "))")
            .font(Typo.mono(10)).foregroundStyle(Theme.amber)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func legacyWorker(_ agent: SubagentStatus) -> some View {
        Button {
            openSubagent(agent)
        } label: {
            HStack(spacing: 10) {
                RoleTile(role: agent.agentType)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName).font(Typo.display(12)).foregroundStyle(Theme.tx)
                    Text(agent.description).font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(2)
                    Text("Plan, estimates and check-in unavailable").font(Typo.text(10)).foregroundStyle(Theme.tx3)
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

    private var roster: some View {
        DisclosureGroup("Team roster · \(team.count) specialists") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(team) { member in
                    HStack(alignment: .top, spacing: 10) {
                        RoleTile(role: member.skills.first ?? member.name)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(member.name) · \(member.skills.joined(separator: ", "))")
                                .font(Typo.text(11.5)).foregroundStyle(Theme.tx2)
                            Text(member.owns).font(Typo.text(10.5)).foregroundStyle(Theme.tx3)
                        }
                    }
                }
            }.padding(.top, 12)
        }
        .font(Typo.text(12)).tint(Theme.tx2).foregroundStyle(Theme.tx2).cardSurface()
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
                SectionLabel("Acceptance")
                Text("\(done) / \(session.taskIDs.count) tasks passed QA").font(Typo.display(15)).foregroundStyle(
                    Theme.tx)
                MeterBar(
                    value: session.taskIDs.isEmpty ? 0 : Double(done) / Double(session.taskIDs.count), tint: Theme.green
                )
                Text("A returned worker still needs independent QA before its task is accepted.")
                    .font(Typo.text(11)).foregroundStyle(Theme.tx3).fixedSize(horizontal: false, vertical: true)
            }
            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Needs attention", trailing: "\(waiting.count)")
                    ForEach(waiting) { block in
                        Button {
                            openBlock(block)
                        } label: {
                            Label(block.title, systemImage: "hand.raised")
                                .font(Typo.text(11.5)).foregroundStyle(Theme.amber)
                                .multilineTextAlignment(.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Check-ins & memory")
                if let coordination = session.coordination {
                    if !coordination.contextSummary.isEmpty {
                        Text(coordination.contextSummary).font(Typo.text(11)).foregroundStyle(Theme.tx2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(coordination.workers) { context($0) }
                    if coordination.workers.isEmpty { unavailableContext }
                } else {
                    unavailableContext
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
                                    .font(Typo.text(11)).foregroundStyle(Theme.tx2)
                                    .multilineTextAlignment(.leading)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top, 8)
                }.font(Typo.text(11.5)).tint(Theme.tx3).foregroundStyle(Theme.tx2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailableContext: some View {
        Text(
            "Check-ins, context usage and checkpoints appear when the lead records them. Unknown limits stay unreported."
        )
        .font(Typo.text(11)).foregroundStyle(Theme.tx3).fixedSize(horizontal: false, vertical: true)
    }

    private func context(_ work: LeadWork) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                StateDot(color: LeadDisplay.tint(work), live: work.state == "running" && work.runtimeRunning != false)
                Text(work.title.nonEmpty ?? work.id).font(Typo.text(11.5, .medium)).foregroundStyle(Theme.tx2)
            }
            Text("Check-in \(work.updatedAt.map { AgentUsage.ago($0) } ?? "unreported")")
                .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            if let used = work.contextTokens, let window = work.contextWindow, window > 0 {
                let ratio = Double(used) / Double(window)
                HStack {
                    Text("\(AgentUsage.short(used)) / \(AgentUsage.short(window)) context")
                    Spacer(minLength: 4)
                    Text(String(format: "%.0f%%", ratio * 100))
                }
                .font(Typo.mono(10)).foregroundStyle(Theme.tx2)
                MeterBar(value: ratio, tint: ratio >= 0.75 ? Theme.red : ratio >= 0.6 ? Theme.amber : Theme.green)
                if ratio >= 0.6 {
                    Text(ratio >= 0.75 ? "Compaction threshold reached" : "Checkpoint threshold reached")
                        .font(Typo.text(10)).foregroundStyle(ratio >= 0.75 ? Theme.red : Theme.amber)
                }
            } else {
                Text("Context: \(LeadDisplay.tokens(work.contextTokens)) / \(LeadDisplay.tokens(work.contextWindow))")
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            }
            if !work.contextSource.isEmpty {
                Text(work.contextSource).font(Typo.text(10)).foregroundStyle(Theme.tx3)
            }
            DisclosureGroup(work.checkpoint.isEmpty ? "No checkpoint recorded" : "Saved checkpoint") {
                Text(work.checkpoint.nonEmpty ?? "A checkpoint has not been reported.")
                    .font(Typo.text(11)).foregroundStyle(Theme.tx2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
            }
            .font(Typo.text(10.5)).tint(Theme.tx3).foregroundStyle(Theme.tx3)
        }
        .cardSurface(radius: 9, padding: 12)
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
        case "done": return "QA passed"
        case "review": return "QA pending"
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
