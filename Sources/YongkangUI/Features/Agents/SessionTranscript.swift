import SwiftUI
import YongkangCore

/// Any agent session read the way its subagents are read: off its own transcript, as
/// steps. A session is an agent before it is anything else — a lead, the product voice,
/// an engineer walking the user through a block — and what it has actually said and done
/// is the answer to "what is it doing". The terminal shows the same work as a wall of
/// ANSI that scrolls away, and is a click away in the top bar for anyone who wants to
/// type at it.
///
/// A lead keeps the batch beside it, because a lead is watched for its whole batch rather
/// than for itself; every other session gets what it spawned and what it is holding.
package struct SessionTranscript: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let blocks: [UserBlock]
    let lines: [TranscriptLine]
    let source: URL?
    let openTask: (String) -> Void
    let openBlock: (UserBlock) -> Void
    let openSubagent: (SubagentStatus) -> Void
    /// Typed into the session's own process, the same pipe that hands a running lead more
    /// work — so answering an agent does not mean leaving the transcript for its terminal.
    let send: (String) -> Void

    @State private var reply = ""

    package init(
        session: CodeSession,
        cards: [NotebookCard],
        blocks: [UserBlock],
        lines: [TranscriptLine],
        source: URL?,
        openTask: @escaping (String) -> Void,
        openBlock: @escaping (UserBlock) -> Void,
        openSubagent: @escaping (SubagentStatus) -> Void,
        send: @escaping (String) -> Void
    ) {
        self.session = session
        self.cards = cards
        self.blocks = blocks
        self.lines = lines
        self.source = source
        self.openTask = openTask
        self.openBlock = openBlock
        self.openSubagent = openSubagent
        self.send = send
    }

    private var state: AgentState { AgentState.of(lines: lines, exited: session.exited) }

    package var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TranscriptHeader(
                    role: session.isEngineeringLead ? "lead" : session.title,
                    title: session.title, subtitle: subtitle,
                    lines: lines, state: state)
                TranscriptTimeline(lines: lines)
                composer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            if session.isEngineeringLead {
                LeadInspector(
                    session: session, cards: cards, blocks: blocks,
                    openTask: openTask, openBlock: openBlock)
            } else {
                SessionInspector(
                    session: session, blocks: blocks, source: source,
                    openBlock: openBlock, openSubagent: openSubagent)
            }
        }
    }

    /// One line to type back at the agent. Enter sends; a dead session has nothing to
    /// send to, so it says that instead.
    @ViewBuilder private var composer: some View {
        HStack(spacing: 9) {
            TextField(
                session.exited ? "Session has exited" : "Reply to \(session.title)…",
                text: $reply
            )
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Theme.tx)
            .onSubmit(dispatch)
            .disabled(session.exited)
            Button(action: dispatch) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 17))
                    .foregroundStyle(canSend ? Theme.accent : Theme.tx4)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.wellLine, lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private var canSend: Bool {
        !session.exited && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func dispatch() {
        guard canSend else { return }
        send(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        reply = ""
    }

    private var subtitle: String {
        let running = session.activeSubagents.count
        let agents = running == 0 ? "" : " · \(running) agent\(running == 1 ? "" : "s") running"
        guard session.isEngineeringLead else {
            return (session.agent?.displayName ?? "session") + " · " + state.label.lowercased() + agents
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

    /// Blocks this session raised and is still sitting on, including Product's link back
    /// to an in-progress proposal discussion.
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
                        .font(Typography.body).foregroundStyle(Theme.tx)
                    Spacer(minLength: 0)
                    NotebookStyle.pill(
                        session.exited ? "exited" : "live",
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
                        Button {
                            openSubagent(subagent)
                        } label: {
                            HStack(spacing: 9) {
                                RoleTile(role: subagent.agentType, size: 20)
                                Text(subagent.displayName).font(Typography.body)
                                    .foregroundStyle(Theme.tx2).lineLimit(1)
                                Text(subagent.agentType).font(Typography.monoCaption)
                                    .foregroundStyle(Theme.tx4).lineLimit(1)
                                Spacer(minLength: 0)
                                StateDot(
                                    color: subagent.running ? Theme.accent : Theme.green,
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
                        Button {
                            openBlock(block)
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "hand.raised").font(.system(size: 12))
                                    .foregroundStyle(Theme.amber)
                                Text(block.title).font(Typography.body).foregroundStyle(Theme.tx2)
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
