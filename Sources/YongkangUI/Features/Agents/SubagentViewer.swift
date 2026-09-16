import SwiftUI
import YongkangCore

/// A subagent's own work, read live off its transcript: the task it was given, every tool
/// it called, and what came back. A subagent shares its parent's session id — there is no
/// separate session to attach to for just this one task — so this, kept fresh by the same
/// poll that finds the subagent itself, is the closest thing to watching it work.
///
/// The timeline is `TranscriptTimeline`, the same one the lead is read through; what is
/// particular to a subagent is the header above it and the task in the inspector.
package struct SubagentViewer: View {
    let session: CodeSession
    let subagent: SubagentStatus
    let lines: [TranscriptLine]
    let task: NotebookCard?
    let openTask: (String) -> Void

    @State private var checklist: [NotebookContent.ChecklistItem] = []

    package init(
        session: CodeSession,
        subagent: SubagentStatus,
        lines: [TranscriptLine],
        task: NotebookCard?,
        openTask: @escaping (String) -> Void
    ) {
        self.session = session
        self.subagent = subagent
        self.lines = lines
        self.task = task
        self.openTask = openTask
    }

    package var body: some View {
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
        TranscriptHeader(
            role: subagent.agentType, title: subagent.displayName,
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
                    Button {
                        openTask(task.id)
                    } label: {
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
                        SectionLabel(
                            "Done when",
                            trailing: "\(checklist.filter(\.done).count) of \(checklist.count)")
                        ForEach(Array(checklist.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.done ? Theme.green : Theme.tx4)
                                    .padding(.top, 1)
                                Text(item.text).font(Typo.text(11.5))
                                    .foregroundStyle(item.done ? Theme.prose : Theme.tx3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Task")
                    Text(
                        "This agent's name matches no task in the batch — a review or "
                            + "compaction agent, most likely."
                    )
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

/// The file the timeline was read from, and the way out to it. The same block under every
/// agent — what is on screen is a rendering, and this is where the real thing lives.
struct TranscriptSource: View {
    let url: URL?
    /// What the file is, for the heading and the button. A transcript everywhere it was
    /// written for; the roster and skill files on a team member reuse the same block.
    var label = "Transcript"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            Text(url?.path ?? "Not on disk yet.")
                .font(Typo.mono(9.5)).foregroundStyle(Theme.tx3)
                .lineLimit(3).truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.well))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.wellLine, lineWidth: 1))
            Button {
                if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } label: {
                Label("Reveal \(label.lowercased())", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.console)
            .disabled(url == nil)
        }
    }
}
