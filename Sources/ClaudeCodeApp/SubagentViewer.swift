import SwiftUI

/// A subagent's own work, read live off its transcript: the task it was given, every tool
/// it called, and what came back. A subagent shares its parent's session id — there is no
/// separate session to attach to for just this one task — so this, kept fresh by the same
/// poll that finds the subagent itself, is the closest thing to watching it work.
///
/// Laid out the way Claude Code's own view is: the brief, what the agent has said back,
/// and everything in between collapsed to one line per run of tool work — "Searched for 1
/// pattern, read 14 files, ran 8 shell commands". Printing every call and every result
/// buries the two things worth reading. A run opens when you click it, so nothing is lost;
/// it is just not all shouted at once.
struct SubagentViewer: View {
    let session: CodeSession
    let subagent: SubagentStatus
    let lines: [TranscriptLine]
    let task: NotebookCard?
    let openTask: (String) -> Void

    @State private var checklist: [NotebookContent.ChecklistItem] = []
    /// Runs of tool work the reader has opened, by position — position rather than identity
    /// because the transcript is re-parsed every two seconds while the agent works.
    @State private var opened: Set<Int> = []

    private var steps: [TranscriptStep] { TranscriptSteps.steps(lines) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if lines.isEmpty {
                    empty
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(steps) { item in
                                    step(item, last: item.id == steps.count - 1).id(item.id)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                        }
                        .onAppear { scrollToEnd(proxy) }
                        .onChange(of: lines.count) { _ in scrollToEnd(proxy) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            inspector
        }
        .task(id: task?.id) { load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            RoleTile(role: subagent.agentType, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(subagent.agentType).font(Typo.display(15))
                Text("spawned by \(session.title)"
                     + (task.map { " · on \($0.title)" } ?? ""))
                    .font(Typo.text(11)).foregroundStyle(Theme.tx3)
            }
            Spacer(minLength: 12)
            NotebookStyle.chip("\(steps.count) steps", mono: true)
            NotebookStyle.pill(subagent.running ? "Running" : "Done",
                               subagent.running ? Theme.accent : Theme.green,
                               live: subagent.running)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - One step

    @ViewBuilder private func step(_ item: TranscriptStep, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            spine(item, last: last)
            switch item.kind {
            case .task, .say:
                VStack(alignment: .leading, spacing: 6) {
                    // Only the brief is labelled. What the agent says needs no heading —
                    // it is the one thing on the screen written for a person to read.
                    if item.kind == .task {
                        Text("TASK").font(Typo.section).tracking(1.4)
                            .foregroundStyle(tint(item.kind))
                    }
                    Text(item.text)
                        .font(Typo.text(12.5))
                        .foregroundStyle(Color(hex: 0xC7D0DC))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: 11, padding: 13)
            case .skill:
                HStack(spacing: 8) {
                    Text(item.text).font(Typo.mono(11.5)).foregroundStyle(Theme.tx)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
            case .work:
                work(item)
            }
        }
        .padding(.bottom, item.kind == .work || item.kind == .skill ? 6 : 12)
    }

    /// The collapsed run: one line of what happened, and the calls themselves only if you
    /// ask for them.
    @ViewBuilder private func work(_ item: TranscriptStep) -> some View {
        let isOpen = opened.contains(item.id)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isOpen { opened.remove(item.id) } else { opened.insert(item.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.tx4)
                    Text(item.text).font(Typo.text(12)).foregroundStyle(Theme.tx3)
                    if item.errors > 0 {
                        NotebookStyle.pill("\(item.errors) failed", Theme.amber)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.detail) { line in call(line) }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func call(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if line.label == "Tool" {
                // `Read(file_path: …)` — the name carries, the arguments trail off.
                let split = line.text.firstIndex(of: "(")
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(split.map { String(line.text[..<$0]) } ?? line.text)
                        .foregroundStyle(Theme.accent)
                    Text(split.map { String(line.text[$0...]) } ?? "")
                        .foregroundStyle(Theme.tx2)
                }
                .font(Typo.mono(11))
                .textSelection(.enabled)
            } else {
                Text(line.text)
                    .font(Typo.mono(10.5))
                    .foregroundStyle(line.isError ? Color(hex: 0xF1BDBD) : Theme.tx2)
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0E1116)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(line.isError ? Theme.red.opacity(0.25)
                                                   : Color(hex: 0x1E242F), lineWidth: 1))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spine(_ item: TranscriptStep, last: Bool) -> some View {
        ZStack(alignment: .top) {
            if !last {
                Rectangle().fill(Theme.line).frame(width: 1).padding(.top, 22)
            }
            switch item.kind {
            case .task, .say:
                Image(systemName: item.kind == .task ? "arrow.down.right.circle" : "bubble.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint(item.kind))
                    .frame(width: 23, height: 23)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x12161E)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hex: 0x242B37), lineWidth: 1))
            default:
                Circle().fill(tint(item.kind))
                    .frame(width: 6, height: 6)
                    .frame(width: 23, height: 23)
            }
        }
        .frame(width: 23)
    }

    private func tint(_ kind: TranscriptStep.Kind) -> Color {
        switch kind {
        case .task: return Theme.violet
        case .say: return Theme.green
        case .skill: return Theme.accent
        case .work: return Theme.tx4
        }
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
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Transcript")
                Text(subagent.transcriptURL.path)
                    .font(Typo.mono(9.5)).foregroundStyle(Theme.tx3)
                    .lineLimit(3).truncationMode(.middle)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x12161E)))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color(hex: 0x1E242F), lineWidth: 1))
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([subagent.transcriptURL])
                } label: {
                    Label("Reveal transcript", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.console)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass").font(.system(size: 22)).foregroundStyle(Theme.tx4)
            Text("Nothing recorded yet.").font(Typo.text(13)).foregroundStyle(Theme.tx3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        checklist = task.map { NotebookIndex.checklist(at: $0.url) } ?? []
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = lines.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }
}
