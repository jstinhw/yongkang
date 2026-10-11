import SwiftUI
import YongkangCore

/// The rows of one file's diff, and — when a task owns the file — a comment under any line
/// you click. The same rows on a task's review page and on a file's own page, so a comment
/// left in either place is the same comment.
struct DiffLines: View {
    let path: String
    let lines: [DiffLine]
    /// Nil when no task claims the file: there is no agent a comment could go to.
    let draft: Binding<ReviewDraft>?

    /// The row a comment is being written under, and what has been typed so far.
    @State private var composing: UUID?
    @State private var comment = ""

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                row(line)
                ForEach(saved(on: line)) { note(for: $0) }
                if composing == line.id { composer(for: line) }
            }
        }
    }

    private func row(_ line: DiffLine) -> some View {
        let ink: Color
        let wash: Color
        switch line.kind {
        case .add:
            ink = Theme.insertion
            wash = Theme.green.opacity(0.07)
        case .remove:
            ink = Theme.problem
            wash = Theme.red.opacity(0.07)
        case .hunk:
            ink = Theme.hunk
            wash = Theme.accent.opacity(0.06)
        case .context:
            ink = Theme.unchanged
            wash = .clear
        }
        let sign = line.kind == .add ? "+" : (line.kind == .remove ? "−" : " ")
        return HStack(spacing: 0) {
            Text(line.old).frame(width: 44, alignment: .trailing)
                .foregroundStyle(Theme.tx4).padding(.trailing, 10)
            Text(line.new).frame(width: 44, alignment: .trailing)
                .foregroundStyle(Theme.tx4).padding(.trailing, 12)
            Text(sign).frame(width: 12, alignment: .leading).foregroundStyle(ink)
            Text(line.text).foregroundStyle(ink).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        // `code`, not `mono`: a diff is the pane the bigger monospace role exists for. The
        // gutters ride the same font, so the numbers and the code stay on one baseline.
        .font(Typography.code)
        .frame(height: 19)
        .padding(.horizontal, 8)
        .background(wash)
        .overlay { if composing == line.id { Rectangle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1) } }
        .contentShape(Rectangle())
        .onTapGesture {
            guard draft != nil, line.kind != .hunk else { return }
            composing = composing == line.id ? nil : line.id
            comment = ""
        }
        .help(draft != nil && line.kind != .hunk ? "Click to comment on this line" : "")
        // A click here opens a comment, so the line's code is copied from the menu.
        .copyable(line.text, label: "Copy line")
    }

    /// A comment is pinned to its line by number and code together, so an agent's later
    /// edit that shifts the file does not move it onto a line it was never about.
    private func saved(on line: DiffLine) -> [ReviewComment] {
        (draft?.wrappedValue.comments ?? []).filter {
            $0.path == path && $0.line == Self.number(of: line) && $0.code == line.text
        }
    }

    static func number(of line: DiffLine) -> String { line.new.isEmpty ? line.old : line.new }

    private func note(for saved: ReviewComment) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("You").font(Typography.body(.medium)).foregroundStyle(Theme.tx)
            NotebookStyle.pill("draft", Theme.violet)
            Text(saved.text).font(Typography.body).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                draft?.wrappedValue.comments.removeAll { $0.id == saved.id }
            } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.consoleGhost)
            .accessibilityLabel("Delete this comment")
        }
        .frame(width: 560, alignment: .leading)
        .cardSurface(radius: 10, padding: 10)
        .padding(.leading, 118)
        .padding(.vertical, 6)
    }

    private func composer(for line: DiffLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What should the agent change here?", text: $comment, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .font(Typography.body)
                .foregroundStyle(Theme.tx)
            HStack(spacing: 6) {
                Text("\(path):\(Self.number(of: line)) · sent with your review")
                    .font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 8)
                Button("Cancel") { composing = nil }.buttonStyle(.consoleGhost)
                Button {
                    draft?.wrappedValue.comments.append(
                        ReviewComment(
                            path: path, line: Self.number(of: line),
                            code: line.text, text: comment))
                    composing = nil
                } label: {
                    Label("Add comment", systemImage: "text.bubble")
                }
                .buttonStyle(.console)
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(width: 560, alignment: .leading)
        .cardSurface(radius: 10, padding: 10, border: Theme.accent.opacity(0.45))
        .padding(.leading, 118)
        .padding(.vertical, 6)
    }
}
