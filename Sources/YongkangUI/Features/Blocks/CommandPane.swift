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
    /// Each file as it first appeared here, so one rewritten while the user was reading it says
    /// so instead of changing quietly under them.
    @State private var firstSeen: [String: BlockCommand.Content] = [:]
    @State private var copied = false
    /// The `PATH` of the shell a session runs in, read once: nil until it is, or if it can't be.
    @State private var login: [String]?
    @State private var loginRead = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                heading
                commandCard
                // Only a read of this very line: one of the last command would show its files
                // under this one, for as long as the read takes.
                if let command, command.line == line {
                    touches(command)
                    if !command.programs.isEmpty { programs(command) }
                    runs(command)
                } else {
                    Text("Reading what it runs…").font(Typography.body).foregroundStyle(Theme.tx3)
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
        .task {
            login = await BlockCommand.loginPath()
            loginRead = true
        }
    }

    /// Off the main thread: a script can be half a megabyte, and every line is matched.
    private func watch() async {
        let line = line
        let directory = directory
        firstSeen = [:]
        while !Task.isCancelled {
            let held = command?.line == line ? command : nil
            let folders = BlockCommand.path(login: login)
            let next = await Task.detached {
                BlockCommand.read(line, in: directory, reusing: held, searching: folders)
            }.value
            // The block's command moved on while this read ran: its task reads the new one, and
            // this one's answer must not land on top of it.
            guard !Task.isCancelled else { return }
            if next != command {
                command = next
                let seen = Dictionary(next.files.map { ($0.id, $0.content) }) { first, _ in first }
                firstSeen = firstSeen.merging(seen) { first, _ in first }
            }
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
            Text(BlockCommand.visible(line)).font(Typography.code).foregroundStyle(Theme.tx)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.wellLine, lineWidth: 1))
            // A relative path names a different file in another folder, so the folder is said.
            Text(
                """
                Paste it after `!` in the session, which runs in \(Text(verbatim: folder).font(Typography.mono)). \
                In another terminal, `cd` there first.
                """
            )
            .font(Typography.caption).foregroundStyle(Theme.tx3)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folder: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return directory.path.hasPrefix(home + "/") ? "~" + directory.path.dropFirst(home.count) : directory.path
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
            if command.files.isEmpty, command.unresolved.isEmpty {
                Text(
                    "No script behind it that Yongkang could find."
                )
                .font(Typography.body).foregroundStyle(Theme.tx2)
            }
            ForEach(command.unresolved, id: \.self) { word in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(BlockCommand.visible(word)).font(Typography.code(.semibold)).foregroundStyle(Theme.tx)
                        Spacer(minLength: 8)
                        Text("can't tell which file").font(Typography.caption).foregroundStyle(Theme.amber)
                    }
                    Text(
                        "The shell fills this in when it runs — a variable, a pattern or a command's output — so "
                            + "Yongkang can't show what it names. Ask the agent to write the path out."
                    )
                    .font(Typography.body).foregroundStyle(Theme.tx2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .cardSurface(radius: 8, padding: 10)
            }
            ForEach(command.files) { file in
                CommandFile(
                    file: file, flagged: command.flagged(file.url),
                    changed: firstSeen[file.id].map { $0 != file.content } ?? false)
            }
            if command.truncated {
                Text(
                    "It runs more than the \(BlockCommand.fileLimit) files shown here. Ask the agent to make it "
                        + "one script before you run it."
                )
                .font(Typography.body).foregroundStyle(Theme.amber)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Each program it runs by name and where that is, so a script early on the `PATH` standing in
    /// for `git` shows as itself.
    private func programs(_ command: BlockCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                section("Programs it runs")
                Spacer()
                Text(
                    loginRead
                        ? (login == nil ? "your shell's PATH couldn't be read" : "on your shell's PATH")
                        : "reading your shell's PATH…"
                )
                .font(Typography.caption).foregroundStyle(loginRead && login == nil ? Theme.amber : Theme.tx3)
            }
            VStack(spacing: 0) {
                ForEach(command.programs) { program in
                    if program.id != command.programs.first?.id { Divider().overlay(Theme.line) }
                    programRow(program)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
        }
    }

    private func programRow(_ program: BlockCommand.Program) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(program.name).font(Typography.code(.semibold)).foregroundStyle(Theme.tx)
                Spacer(minLength: 8)
                Text(program.found.first?.path ?? "not on PATH: a shell builtin, or not installed")
                    .font(Typography.mono).foregroundStyle(Theme.tx3)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            if program.found.count > 1 {
                Text(
                    "Also at \(program.found.dropFirst().map(\.path).joined(separator: ", ")). "
                        + "Which one runs depends on the order of the PATH."
                )
                .font(Typography.caption).foregroundStyle(Theme.amber)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private func section(_ label: String) -> some View {
        Text(label.uppercased()).font(Typography.section).tracking(1.4).foregroundStyle(Theme.tx2)
    }
}

extension BlockCommand.Kind {
    var symbol: String {
        switch self {
        case .hidden: "eye.slash"
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
