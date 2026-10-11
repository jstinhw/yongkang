import AppKit
import SwiftUI
import YongkangCore

/// A command an agent needs the user to run, and what it would run, as it is on disk.
///
/// Read again every two seconds while it is on screen: the agent may still be writing the
/// script, and what is shown has to be what runs. The agent's account of what it does is in
/// its reply beside this; nothing here comes from the agent but the command line.
struct CommandPane: View {
    let line: String
    let directory: URL

    @State private var command: BlockCommand?
    @State private var copied = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                heading
                commandCard
                if let command {
                    touches(command)
                    runs(command)
                }
                Text(
                    "Shown: every file the command names, and each script a shown script names beside "
                        + "itself. Anything a script downloads, or finds by a path it builds while running, is not."
                )
                .font(Typography.caption).foregroundStyle(Theme.tx3)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(Theme.panel)
        .task(id: line) { await watch() }
    }

    /// Off the main thread: a script can be half a megabyte, and every line is matched.
    private func watch() async {
        let line = line
        let directory = directory
        while !Task.isCancelled {
            let held = command?.line == line ? command : nil
            let next = await Task.detached {
                if let held, held.isCurrent { return held }
                return BlockCommand.read(line, in: directory)
            }.value
            if next != command { command = next }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run this yourself").font(Typography.headline).foregroundStyle(Theme.tx)
            Text(
                "The agent is asking you to run this. Below is exactly what would run, read from disk "
                    + "rather than described by the agent. Yongkang shows it; it has not checked that it is safe."
            )
            .font(Typography.body).foregroundStyle(Theme.tx2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commandCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                section("Command")
                Spacer()
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                    .buttonStyle(.consolePrimary)
            }
            Text(line).font(Typography.code).foregroundStyle(Theme.tx)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.wellLine, lineWidth: 1))
            Text("Paste it after `!` in the session, or into your own terminal.")
                .font(Typography.caption).foregroundStyle(Theme.tx3)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func touches(_ command: BlockCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                section("What it touches")
                Spacer()
                Text("a pattern match, not a review").font(Typography.caption).foregroundStyle(Theme.tx3)
            }
            if command.flags.isEmpty {
                Text("Nothing matched what Yongkang looks for. That is not a review: read what runs.")
                    .font(Typography.body).foregroundStyle(Theme.tx2)
            } else {
                VStack(spacing: 0) {
                    ForEach(command.flags) { flag in
                        if flag.kind != command.flags.first?.kind { Divider().overlay(Theme.line) }
                        flagRow(flag)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
            }
        }
    }

    private func flagRow(_ flag: BlockCommand.Flag) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: flag.kind.symbol).font(.system(size: 11)).foregroundStyle(Theme.amber)
                .frame(width: 14)
            Text(flag.kind.label).font(Typography.body).foregroundStyle(Theme.prose)
            Spacer(minLength: 12)
            Text(Self.places(flag)).font(Typography.mono).foregroundStyle(Theme.tx3)
                .lineLimit(2).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    /// `finish.sh:12, 14 · rewrite.sh:19`, in the order the files are shown.
    static func places(_ flag: BlockCommand.Flag) -> String {
        let names = flag.places.map { $0.file?.lastPathComponent ?? "command" }
        let order = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return order.map { name in
            guard name != "command" else { return name }
            let lines = flag.places.filter { $0.file?.lastPathComponent == name }.map { String($0.line) }
            return name + ":" + lines.joined(separator: ", ")
        }
        .joined(separator: " · ")
    }

    private func runs(_ command: BlockCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                let count = command.files.count
                section(count == 0 ? "What runs" : "What runs · \(count) \(count == 1 ? "file" : "files")")
                Spacer()
                if count > 0 { Text("in full").font(Typography.caption).foregroundStyle(Theme.tx3) }
            }
            if command.files.isEmpty {
                Text("No file of its own: the command above is all of it.")
                    .font(Typography.body).foregroundStyle(Theme.tx2)
            }
            ForEach(command.files) { file in
                CommandFile(file: file, flagged: command.flagged(file.url))
            }
        }
    }

    private func section(_ label: String) -> some View {
        Text(label.uppercased()).font(Typography.section).tracking(1.4).foregroundStyle(Theme.tx2)
    }
}

extension BlockCommand.Kind {
    var symbol: String {
        switch self {
        case .network: "arrow.up.arrow.down"
        case .history: "arrow.triangle.branch"
        case .remote: "link"
        case .discards: "arrow.uturn.backward"
        case .deletes: "trash"
        case .admin: "lock"
        case .path: "terminal"
        case .fetchedCode: "arrow.down.circle"
        case .secrets: "key"
        case .settings: "gearshape"
        }
    }
}
