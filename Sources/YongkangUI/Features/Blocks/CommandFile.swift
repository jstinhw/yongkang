import SwiftUI
import YongkangCore

/// One file a command runs, whole. Long lines wrap rather than run off the edge: the end of a
/// line is exactly where something would hide.
struct CommandFile: View {
    let file: BlockCommand.File
    /// The line numbers a flag points at, marked in the gutter.
    let flagged: Set<Int>
    /// Rewritten since it first appeared in the pane: what was read is not what runs now.
    var changed = false

    /// A withheld file the user asked to see.
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if case .text(let text) = file.content {
                if file.withheld == nil || revealed {
                    Divider().overlay(Theme.line)
                    lines(text)
                } else {
                    withheld
                }
            } else {
                Text(message).font(Typography.body).foregroundStyle(Theme.tx2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(file.url.lastPathComponent).font(Typography.code(.semibold)).foregroundStyle(Theme.tx)
                Spacer(minLength: 8)
                Text(detail).font(Typography.caption).foregroundStyle(shown ? Theme.tx3 : Theme.amber)
                    .lineLimit(1)
            }
            Text(file.url.path).font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            if changed {
                Text("Changed while it was on screen. Read it again before you run the command.")
                    .font(Typography.caption(.semibold)).foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    /// Asked for, never assumed: a token in a data file is drawn only on a click.
    private var withheld: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(
                file.withheld == .secretName
                    ? "Named like a key or a token, so it isn't drawn until you ask. If the command runs it, "
                        + "read it before you run the command."
                    : "Data the command reads, not a script it runs. It isn't drawn until you ask: it may hold a token."
            )
            .font(Typography.body).foregroundStyle(Theme.tx2)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Show") { revealed = true }.buttonStyle(.console)
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

    private var shown: Bool {
        if case .text = file.content { return true }
        return false
    }

    /// Who named it and how big it is, or why it is not drawn.
    private var detail: String {
        switch file.content {
        case .text(let text):
            let count = text.components(separatedBy: "\n").count
            let parts = [
                file.namedBy.map { $0 == "PATH" ? "found on PATH" : "named in \($0)" },
                "\(count) \(count == 1 ? "line" : "lines")",
                file.modified.map { "written \(Self.when($0))" },
            ]
            return parts.compactMap { $0 }.joined(separator: " · ")
        case .missing: return "not found"
        case .binary, .tooLarge: return "can't be shown"
        }
    }

    private var message: String {
        switch file.content {
        case .text: return ""
        case .missing:
            return "The command names it, but it isn't there. Don't run the command until it shows here."
        case .binary(let bytes):
            return "A program, not text (\(Self.size(bytes))). Yongkang can't show what it does. "
                + "Ask the agent what it is and where it came from before you run this."
        case .tooLarge(let bytes):
            return "Too long to show here (\(Self.size(bytes))). Open it yourself before you run this."
        }
    }

    private func lines(_ text: String) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                row(index + 1, line)
            }
        }
        .padding(.vertical, 6)
        .background(Theme.well)
    }

    private func row(_ number: Int, _ line: String) -> some View {
        let marked = flagged.contains(number)
        let comment = line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(Typography.mono).foregroundStyle(marked ? Theme.amber : Theme.tx4)
                .frame(width: 30, alignment: .trailing)
            Text(line.isEmpty ? " " : BlockCommand.visible(line)).font(Typography.mono)
                .foregroundStyle(comment ? Theme.tx3 : Theme.prose)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 10).padding(.vertical, 1)
        .background(marked ? Theme.amber.opacity(0.09) : .clear)
        .overlay(alignment: .leading) {
            if marked { Rectangle().fill(Theme.amber).frame(width: 2) }
        }
    }

    private static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
