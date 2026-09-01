import SwiftUI

/// A subagent's own work, read live off its transcript: the task it was given, every tool
/// it called, and what came back. A subagent shares its parent's session id — there is no
/// separate session to attach to for just this one task — so this, kept fresh by the same
/// poll that finds the subagent itself, is the closest thing to watching it work.
///
/// Laid out as a feed rather than a log: one card per step, tinted and glyphed by kind, so
/// the shape of the work (asked → tried → got back → answered) reads at a glance instead of
/// having to be picked out of a wall of left-aligned text.
struct SubagentViewer: View {
    let session: CodeSession
    let subagent: SubagentStatus
    let lines: [TranscriptLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if lines.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(lines) { row($0).id($0.id) }
                        }
                        .padding(14)
                    }
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: lines.count) { _ in scrollToEnd(proxy) }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: roleGlyph)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(subagent.description).font(.headline)
                Text("\(subagent.agentType) · spawned by \(session.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            status
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The same status language as the board: blue while it works, green once it is done.
    private var status: some View {
        let color = NotebookStyle.color(of: subagent.running ? "active" : "done")
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(subagent.running ? "Running" : "Done")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    /// The specialist skills the lead dispatches, each with its own face — a batch usually
    /// has several of these open at once, and the glyph tells them apart before the words do.
    private var roleGlyph: String {
        let role = subagent.agentType.lowercased()
        if role.contains("frontend") { return "paintbrush" }
        if role.contains("backend") { return "server.rack" }
        if role.contains("qa") { return "checkmark.seal" }
        if role.contains("sre") { return "cloud" }
        if role.contains("fde") { return "person.2" }
        if role.contains("explore") || role.contains("research") { return "magnifyingglass" }
        return "sparkles"
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Nothing recorded yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - One step

    private func row(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: glyph(for: line.label)).font(.caption2)
                Text(line.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(0.5)
            }
            .foregroundStyle(color(for: line.label))
            body(of: line)
        }
        .padding(.vertical, 9)
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A hairline as well as a fill: on a light macOS appearance a card and the page
        // behind it are both near-white, so the fill alone draws no card at all.
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        }
        // The kind's color as a spine down the card, rather than a second block of tinted
        // background competing with the text it is meant to be labelling.
        .overlay(alignment: .leading) {
            Capsule()
                .fill(color(for: line.label).opacity(0.7))
                .frame(width: 3)
                .padding(.vertical, 7)
        }
    }

    @ViewBuilder private func body(of line: TranscriptLine) -> some View {
        switch line.label {
        case "Tool":
            // `Read(file_path: …)` — the name carries, the arguments trail off.
            let split = line.text.firstIndex(of: "(")
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(split.map { String(line.text[..<$0]) } ?? line.text)
                    .fontWeight(.semibold)
                Text(split.map { String(line.text[$0...]) } ?? "")
                    .foregroundStyle(.secondary)
            }
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
        case "Result":
            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        default:
            Text(line.text)
                .font(.callout)
                .textSelection(.enabled)
        }
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
