import SwiftUI

/// A subagent's own work, read live off its transcript: the task it was given, every tool
/// it called, and what came back. A subagent shares its parent's session id — there is no
/// separate session to attach to for just this one task — so this, kept fresh by the same
/// poll that finds the subagent itself, is the closest thing to watching it work.
///
/// The timeline is `TranscriptTimeline`, the same one the lead is read through; what is
/// particular to a subagent is the header above it and the task in the inspector.
struct SubagentViewer: View {
    let session: CodeSession
    let subagent: SubagentStatus
    let lines: [TranscriptLine]
    let task: NotebookCard?
    let openTask: (String) -> Void

    @State private var checklist: [NotebookContent.ChecklistItem] = []

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                TranscriptTimeline(lines: lines)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            inspector
        }
        .task(id: task?.id) { load() }
    }

    // MARK: - Header

    private var header: some View {
        TranscriptHeader(role: subagent.agentType, title: subagent.displayName,
                         subtitle: "\(subagent.agentType) · spawned by \(session.title)"
                             + (task.map { " · on \($0.title)" } ?? ""),
                         lines: lines, state: subagent.running ? .working : .done)
    }

    // MARK: - Inspector

    private var inspector: some View {
        Inspector {
            if let task {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Task")
                    Button { openTask(task.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.title).font(Typo.text(13)).foregroundStyle(Theme.tx)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 7) {
                                Text(task.id).font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                                if !task.status.isEmpty { NotebookStyle.pill(task.status) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !checklist.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel("Done when",
                                     trailing: "\(checklist.filter(\.done).count) of \(checklist.count)")
                        ForEach(Array(checklist.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.done ? Theme.green : Theme.tx4)
                                    .padding(.top, 1)
                                Text(item.text).font(Typo.text(11.5))
                                    .foregroundStyle(item.done ? Color(hex: 0xC7D0DC) : Theme.tx3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Task")
                    Text("This agent's name matches no task in the batch — a review or "
                         + "compaction agent, most likely.")
                        .font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                }
            }
            Spacer(minLength: 0)
            TranscriptSource(url: subagent.transcriptURL)
        }
    }

    private func load() {
        checklist = task.map { NotebookIndex.checklist(at: $0.url) } ?? []
    }
}

/// Who is being watched, above the timeline: the role, who it answers to, how far in it
/// is, and whether it is still working.
struct TranscriptHeader: View {
    let role: String
    let title: String
    let subtitle: String
    let lines: [TranscriptLine]
    let state: AgentState

    var body: some View {
        HStack(spacing: 12) {
            RoleTile(role: role, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.display(15))
                Text(subtitle).font(Typo.text(11)).foregroundStyle(Theme.tx3)
            }
            Spacer(minLength: 12)
            NotebookStyle.chip("\(TranscriptSteps.steps(lines).count) steps", mono: true)
            NotebookStyle.pill(state.label, state.color, live: state.live)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

/// What an agent is doing right now. A subagent's own file answers this exactly — it was
/// spawned to finish one thing and then stops. A session never stops: it works, then sits
/// at its prompt with the answer on screen, which is a different thing from being done and
/// the one the reader has to be told about, because it is their turn.
enum AgentState {
    case starting, working, waiting, done, exited

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .waiting: return "Waiting for you"
        case .done: return "Done"
        case .exited: return "Exited"
        }
    }

    var color: Color {
        switch self {
        case .starting, .working: return Theme.accent
        case .waiting: return Theme.amber
        case .done: return Theme.green
        case .exited: return Theme.tx3
        }
    }

    var live: Bool { self == .starting || self == .working }

    /// A session's state, off the transcript it is already showing: the last thing written
    /// was the agent talking to the user, so it has nothing in flight and is waiting to be
    /// answered. Anything else — a tool call, a result, the brief — is work in progress.
    static func of(lines: [TranscriptLine], exited: Bool) -> AgentState {
        guard !exited else { return .exited }
        guard let last = lines.last else { return .starting }
        return last.label == "Reply" ? .waiting : .working
    }
}

/// The file the timeline was read from, and the way out to it. The same block under every
/// agent — what is on screen is a rendering, and this is where the real thing lives.
struct TranscriptSource: View {
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Transcript")
            Text(url?.path ?? "Not on disk yet.")
                .font(Typo.mono(9.5)).foregroundStyle(Theme.tx3)
                .lineLimit(3).truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x12161E)))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color(hex: 0x1E242F), lineWidth: 1))
            Button {
                if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } label: {
                Label("Reveal transcript", systemImage: "folder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.console)
            .disabled(url == nil)
        }
    }
}
