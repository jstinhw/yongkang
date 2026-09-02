import SwiftUI

/// A subagent's own work, read live off its transcript: the task it was given, every tool
/// it called, and what came back. A subagent shares its parent's session id — there is no
/// separate session to attach to for just this one task — so this, kept fresh by the same
/// poll that finds the subagent itself, is the closest thing to watching it work.
///
/// Laid out as steps on a spine rather than a log: one card per step, glyphed by kind, so
/// the shape of the work (asked → tried → got back → answered) reads at a glance. The
/// inspector beside it is the task the steps are for — the question you would otherwise
/// have to leave the screen to answer.
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
                if lines.isEmpty {
                    empty
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                    step(line, last: index == lines.count - 1).id(line.id)
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
            NotebookStyle.chip("\(lines.count) steps", mono: true)
            NotebookStyle.pill(subagent.running ? "Running" : "Done",
                               subagent.running ? Theme.accent : Theme.green,
                               live: subagent.running)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - One step

    private func step(_ line: TranscriptLine, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .top) {
                if !last {
                    Rectangle().fill(Theme.line)
                        .frame(width: 1)
                        .padding(.top, 24)
                }
                Image(systemName: glyph(for: line.label))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color(for: line.label))
                    .frame(width: 23, height: 23)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x12161E)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hex: 0x242B37), lineWidth: 1))
            }
            .frame(width: 23)

            VStack(alignment: .leading, spacing: 6) {
                Text(line.label.uppercased())
                    .font(Typo.section).tracking(1.4)
                    .foregroundStyle(color(for: line.label))
                body(of: line)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: 11, padding: 13)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder private func body(of line: TranscriptLine) -> some View {
        switch line.label {
        case "Tool":
            // `Read(file_path: …)` — the name carries, the arguments trail off.
            let split = line.text.firstIndex(of: "(")
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(split.map { String(line.text[..<$0]) } ?? line.text)
                    .foregroundStyle(Theme.tx)
                Text(split.map { String(line.text[$0...]) } ?? "")
                    .foregroundStyle(Theme.tx2)
            }
            .font(Typo.mono(11.5))
            .textSelection(.enabled)
        case "Result":
            Text(line.text)
                .font(Typo.mono(10.5))
                .foregroundStyle(Theme.tx2)
                .lineSpacing(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0E1116)))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(hex: 0x1E242F), lineWidth: 1))
                .textSelection(.enabled)
        default:
            Text(line.text)
                .font(Typo.text(12.5))
                .foregroundStyle(Color(hex: 0xC7D0DC))
                .lineSpacing(2)
                .textSelection(.enabled)
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

    private func glyph(for label: String) -> String {
        switch label {
        case "Task": return "arrow.down.right.circle"
        case "Tool": return "terminal"
        case "Result": return "text.alignleft"
        case "Reply": return "bubble.left"
        default: return "circle"
        }
    }

    private func color(for label: String) -> Color {
        switch label {
        case "Task": return Theme.violet
        case "Tool": return Theme.accent
        case "Result": return Theme.tx2
        case "Reply": return Theme.green
        default: return Theme.tx2
        }
    }

    private func load() {
        checklist = task.map { NotebookIndex.checklist(at: $0.url) } ?? []
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = lines.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }
}
