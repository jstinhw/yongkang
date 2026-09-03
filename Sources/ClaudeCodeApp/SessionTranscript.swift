import SwiftUI

/// Any agent session read the way its subagents are read: off its own transcript, as
/// steps. A session is an agent before it is anything else — a lead, the product voice,
/// an engineer walking the user through a block — and what it has actually said and done
/// is the answer to "what is it doing". The terminal shows the same work as a wall of
/// ANSI that scrolls away, and is a click away in the top bar for anyone who wants to
/// type at it.
///
/// A lead keeps the batch beside it, because a lead is watched for its whole batch rather
/// than for itself; every other session gets what it spawned and what it is holding.
struct SessionTranscript: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let blocks: [UserBlock]
    let lines: [TranscriptLine]
    let source: URL?
    let openTask: (String) -> Void
    let openBlock: (UserBlock) -> Void
    let openSubagent: (SubagentStatus) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TranscriptHeader(role: session.isEngineeringLead ? "lead" : session.title,
                                 title: session.title, subtitle: subtitle,
                                 lines: lines, running: !session.exited)
                TranscriptTimeline(lines: lines)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            if session.isEngineeringLead {
                LeadInspector(session: session, cards: cards, blocks: blocks,
                              openTask: openTask, openBlock: openBlock)
            } else {
                SessionInspector(session: session, blocks: blocks, source: source,
                                 openBlock: openBlock, openSubagent: openSubagent)
            }
        }
    }

    private var subtitle: String {
        let running = session.activeSubagents.count
        let agents = running == 0 ? "" : " · \(running) agent\(running == 1 ? "" : "s") running"
        guard session.isEngineeringLead else {
            return (session.agent?.displayName ?? "session") + agents
        }
        let tasks = session.taskIDs.count
        return "\(tasks) task\(tasks == 1 ? "" : "s")"
            + (running == 0 ? " · nothing dispatched yet" : agents)
    }
}

/// A plain session's right-hand column: what it spawned, what it has left waiting on the
/// user, and where its transcript lives. A lead gets `LeadInspector` instead — it is
/// watched for the batch it is running, not for itself.
struct SessionInspector: View {
    let session: CodeSession
    let blocks: [UserBlock]
    let source: URL?
    let openBlock: (UserBlock) -> Void
    let openSubagent: (SubagentStatus) -> Void

    /// Blocks this session raised and is still sitting on. A product proposal names no
    /// session — product writes it and goes home — so nothing shows here for that.
    private var waiting: [UserBlock] {
        blocks.filter { $0.waiting && $0.session == session.id }
    }

    var body: some View {
        Inspector {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Session")
                HStack(spacing: 10) {
                    Image(systemName: session.icon).font(.system(size: 13))
                        .foregroundStyle(Theme.tx3)
                    Text(session.agent?.displayName ?? "session")
                        .font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                    Spacer(minLength: 0)
                    NotebookStyle.pill(session.exited ? "exited" : "live",
                                       session.exited ? Theme.tx3 : Theme.green,
                                       live: !session.exited)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardSurface(padding: 14)

            if !session.subagents.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Agents", trailing: "\(session.activeSubagents.count) running")
                    ForEach(session.subagents) { subagent in
                        Button { openSubagent(subagent) } label: {
                            HStack(spacing: 9) {
                                RoleTile(role: subagent.agentType, size: 20)
                                Text(subagent.description).font(Typo.mono(10.5))
                                    .foregroundStyle(Theme.tx2)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                StateDot(color: subagent.running ? Theme.accent : Theme.green,
                                         live: subagent.running)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Waiting on you")
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

            Spacer(minLength: 0)
            TranscriptSource(url: source)
        }
    }
}
