import SwiftUI

/// The lead as an orchestrator: one lane per assigned task, the specialists it dispatched
/// inside that lane, and where the task has got to in the loop the lead actually runs —
/// dispatch, build, QA, done. Its own transcript and its live terminal are the other two
/// panes of the switch in the top bar.
struct EngineeringLeadBoard: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let blocks: [UserBlock]
    let openTask: (String) -> Void
    let openSubagent: (SubagentStatus) -> Void
    let openBlock: (UserBlock) -> Void

    private var groups: [SubagentTaskGroup] {
        Subagents.grouped(session.activeSubagents, by: session.taskIDs)
    }

    private var unlinked: [SubagentStatus] {
        session.activeSubagents.filter { $0.taskID == nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            content
            inspector
        }
        .background(Theme.bg)
    }

    @ViewBuilder private var content: some View {
        if session.taskIDs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Theme.tx4)
                Text("No tasks assigned to this lead.")
                    .font(Typo.text(13)).foregroundStyle(Theme.tx3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { lane($0) }
                    if !unlinked.isEmpty { unlinkedLane }
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - One task's lane

    private func lane(_ group: SubagentTaskGroup) -> some View {
        let card = cards.first { $0.kind == .task && $0.id == group.id }
        let stage = Stage.of(group, card: card)
        let block = blocks.first { $0.waiting && $0.task == group.id }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Button { openTask(group.id) } label: {
                            Text(card?.title ?? group.id).font(Typo.display(14))
                                .foregroundStyle(Theme.tx)
                        }
                        .buttonStyle(.plain)
                        .disabled(card == nil)
                        if block != nil {
                            NotebookStyle.pill("blocked", Theme.amber)
                        } else if let card, !card.status.isEmpty {
                            NotebookStyle.pill(card.status)
                        }
                        if card == nil { NotebookStyle.pill("missing", Theme.red) }
                    }
                    Text("\(group.id) · \(group.subagents.count) agent"
                         + (group.subagents.count == 1 ? "" : "s"))
                        .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 12)
                chain(stage)
            }
            Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 13).padding(.bottom, 5)
            if group.subagents.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass").font(.system(size: 12)).foregroundStyle(Theme.tx3)
                    Text(waitingReason(for: group.id))
                        .font(Typo.text(12)).foregroundStyle(Theme.tx3)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
            } else {
                ForEach(group.subagents) { worker($0) }
            }
            if let block {
                Button { openBlock(block) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 11))
                        Text("Waiting on you: \(block.title)").font(Typo.text(11.5))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.amber.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.amber.opacity(0.22), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .cardSurface()
    }

    /// What the lead is waiting for, said in its own terms rather than as a blank row.
    private func waitingReason(for taskID: String) -> String {
        let card = cards.first { $0.id == taskID }
        let waits = (card?.dependsOn ?? []).filter { id in
            cards.first { $0.id == id }?.status != "done"
        }
        if !waits.isEmpty { return "Waiting on \(waits.joined(separator: ", "))" }
        if card?.status == "done" { return "Done — every agent on it has finished" }
        return "Waiting for the lead to dispatch a specialist"
    }

    // MARK: - The loop, as a chain

    private enum Stage: Int {
        case dispatch, build, qa, done

        static func of(_ group: SubagentTaskGroup, card: NotebookCard?) -> Stage {
            if card?.status == "done" { return .done }
            if group.subagents.contains(where: { $0.agentType.lowercased().contains("qa") }) {
                return .qa
            }
            return group.subagents.isEmpty ? .dispatch : .build
        }
    }

    private func chain(_ stage: Stage) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(["dispatch", "build", "qa", "done"].enumerated()), id: \.offset) { index, name in
                let tint: Color = index < stage.rawValue ? Theme.green
                    : (index == stage.rawValue ? Theme.accent : Theme.tx3)
                Text(name.uppercased())
                    .font(Typo.mono(9.5)).tracking(0.8)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(index <= stage.rawValue ? tint.opacity(0.12) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(index <= stage.rawValue ? tint.opacity(0.35)
                                                              : Color(hex: 0x242B37), lineWidth: 1))
                if index < 3 {
                    Rectangle().fill(Color(hex: 0x242B37)).frame(width: 14, height: 1)
                }
            }
        }
    }

    // MARK: - One agent

    private func worker(_ subagent: SubagentStatus) -> some View {
        Button { openSubagent(subagent) } label: {
            HStack(spacing: 10) {
                RoleTile(role: subagent.agentType)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subagent.description).font(Typo.mono(11)).foregroundStyle(Theme.tx)
                        .lineLimit(1).truncationMode(.middle)
                    Text(subagent.agentType).font(Typo.text(10)).foregroundStyle(Theme.tx3)
                }
                .frame(width: 230, alignment: .leading)
                Spacer(minLength: 12)
                NotebookStyle.pill(subagent.running ? "Running" : "Done",
                                   subagent.running ? Theme.accent : Theme.green,
                                   live: subagent.running)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tx3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(subagent.description)'s transcript")
    }

    private var unlinkedLane: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Unlinked agents")
            Text("Their names match no task in the batch — a review or compaction agent.")
                .font(Typo.text(11)).foregroundStyle(Theme.tx3)
                .padding(.bottom, 4)
            ForEach(unlinked) { worker($0) }
        }
        .cardSurface()
    }

    private var inspector: some View {
        LeadInspector(session: session, cards: cards, blocks: blocks,
                      openTask: openTask, openBlock: openBlock)
    }
}

/// The lead's right-hand column: how far the batch has got, what is holding it up, and the
/// order it was handed. Shared by the lead's two views — the same facts belong beside its
/// transcript and beside its lanes.
struct LeadInspector: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let blocks: [UserBlock]
    let openTask: (String) -> Void
    let openBlock: (UserBlock) -> Void

    var body: some View {
        let done = session.taskIDs.filter { id in
            cards.contains { $0.id == id && $0.status == "done" }
        }.count
        let waiting = blocks.filter { $0.waiting && session.taskIDs.contains($0.task ?? "") }
        return Inspector {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Batch")
                HStack(spacing: 14) {
                    NotebookStyle.statusRing(done == session.taskIDs.count ? "done" : "active",
                                             progress: session.taskIDs.isEmpty ? 0
                                                : Double(done) / Double(session.taskIDs.count),
                                             size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(done) of \(session.taskIDs.count) done").font(Typo.display(14))
                        Text("\(session.activeSubagents.count) agent"
                             + (session.activeSubagents.count == 1 ? "" : "s") + " running")
                            .font(Typo.text(11)).foregroundStyle(Theme.tx3)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 15)

            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Holding this batch up")
                    ForEach(waiting) { block in
                        Button { openBlock(block) } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "hand.raised").font(.system(size: 12))
                                    .foregroundStyle(Theme.amber)
                                Text(block.title).font(Typo.text(11.5)).foregroundStyle(Theme.tx2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Order")
                ForEach(session.taskIDs, id: \.self) { id in
                    let card = cards.first { $0.id == id }
                    Button { openTask(id) } label: {
                        HStack(spacing: 9) {
                            StateDot(color: NotebookStyle.color(of: card?.status ?? ""))
                            Text(card?.title ?? id).font(Typo.text(11.5))
                                .foregroundStyle(Theme.tx2).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
            Text("The lead never reviews its own work: every finished task goes to a qa-dev "
                 + "agent before it is accepted.")
                .font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineSpacing(2)
        }
    }
}
