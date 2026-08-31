import SwiftUI

/// A subagent's own work, read live off its transcript: the task it was given, every tool
/// it called, and what came back. A subagent shares its parent's session id — there is no
/// separate `claude` session to attach to for just this one task — so this, kept fresh by
/// the same poll that finds the subagent itself, is the closest thing to watching it work.
struct SubagentViewer: View {
    let session: CodeSession
    let subagent: SubagentStatus
    let lines: [ClaudeTranscripts.TranscriptLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if lines.isEmpty {
                Text("Nothing recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(lines) { row($0).id($0.id) }
                        }
                        .padding(12)
                    }
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: lines.count) { _ in scrollToEnd(proxy) }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subagent.description).font(.headline)
                Text("\(subagent.agentType) · spawned by \(session.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(subagent.running ? "Running" : "Done",
                  systemImage: subagent.running ? "circle.dotted" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(subagent.running ? Color.accentColor : .secondary)
        }
        .padding(12)
    }

    private func row(_ line: ClaudeTranscripts.TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(line.label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color(for: line.label))
            Text(line.text)
                .font(line.label == "Task" || line.label == "Reply"
                      ? .callout : .system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for label: String) -> Color {
        switch label {
        case "Task": return .purple
        case "Tool": return .blue
        case "Result": return .secondary
        case "Reply": return .green
        default: return .secondary
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = lines.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }
}
