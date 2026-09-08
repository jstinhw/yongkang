import SwiftUI

/// What the agents actually changed, as a diff you can read without leaving the console.
/// The lead stops at the PR by design, so this is the last thing between an agent's work
/// and your merge — the one screen the old window had no answer for at all.
struct ChangeReview: View {
    let project: Project
    let changes: [FileChange]
    let head: String?
    let branch: String?
    /// The file being read. Empty means nothing picked yet.
    let path: String
    /// What the agents said they were doing, for the screen you land on before picking a
    /// file. Empty when nothing in this project was run through a lead.
    let summary: ChangeSummary
    let select: (String) -> Void
    /// Stages everything and commits. Returns git's own words on failure, nil on success.
    let commit: (String) -> String?

    @State private var lines: [DiffLine] = []
    /// Prefilled from the batch and replaced as tasks finish — until you start typing,
    /// after which what you wrote wins.
    @State private var message = ""
    @State private var suggested = ""
    @State private var failure = ""

    private var change: FileChange? { changes.first { $0.path == path } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if let change {
                        fileHeader(change)
                        diff
                    } else if path.isEmpty {
                        ChangeSummaryPane(summary: summary, changes: changes, select: select)
                    } else {
                        empty
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
                inspector
            }
            commitBar
        }
        .task(id: path) { load() }
        .task(id: summary.commitMessage) {
            if message == suggested { message = summary.commitMessage }
            suggested = summary.commitMessage
        }
    }

    // MARK: - Commit

    /// The end of the review, on every pane of it: read the summary, read the diff, commit
    /// without leaving for a terminal. Nothing is staged until this button is pressed.
    private var commitBar: some View {
        ActionBar {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12)).foregroundStyle(Theme.tx3)
            TextField("Commit message", text: $message)
                .textFieldStyle(.plain)
                .font(Typo.mono(11.5))
                .foregroundStyle(Theme.tx)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.line2, lineWidth: 1))
                .onSubmit(runCommit)
            if !failure.isEmpty {
                Text(failure).font(Typo.mono(10.5)).foregroundStyle(Theme.red)
                    .lineLimit(2).frame(maxWidth: 260, alignment: .leading)
            }
            Button(action: runCommit) {
                Label("Commit all changes", systemImage: "checkmark.seal")
            }
            .buttonStyle(.consolePrimary)
            .disabled(changes.isEmpty
                      || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func runCommit() {
        guard !changes.isEmpty else { return }
        failure = commit(message) ?? ""
        // A committed message left in the box is one Return away from a second, empty
        // commit — so a success clears it and the next batch fills it in again.
        if failure.isEmpty { message = ""; suggested = "" }
    }

    // MARK: - Diff

    private func fileHeader(_ change: FileChange) -> some View {
        HStack(spacing: 10) {
            Image(systemName: change.untracked ? "doc.badge.plus" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(change.untracked ? Theme.green : Theme.tx3)
            Text(change.path).font(Typo.mono(11.5)).foregroundStyle(Theme.tx).lineLimit(1)
                .truncationMode(.head)
            Text("+\(change.added)").font(Typo.mono(10.5)).foregroundStyle(Theme.green)
            Text("−\(change.removed)").font(Typo.mono(10.5)).foregroundStyle(Theme.red)
            Spacer(minLength: 12)
            if change.untracked {
                NotebookStyle.pill("new file", Theme.green)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var diff: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { row($0) }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ line: DiffLine) -> some View {
        let ink: Color
        let wash: Color
        switch line.kind {
        case .add: ink = Color(hex: 0xB6EBD5); wash = Theme.green.opacity(0.07)
        case .remove: ink = Color(hex: 0xF1BDBD); wash = Theme.red.opacity(0.07)
        case .hunk: ink = Color(hex: 0x5F9FE0); wash = Theme.accent.opacity(0.06)
        case .context: ink = Color(hex: 0x8C97A6); wash = .clear
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
        .font(Typo.mono(11))
        .frame(height: 19)
        .padding(.horizontal, 8)
        .background(wash)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal").font(.system(size: 24)).foregroundStyle(Theme.tx4)
            Text(changes.isEmpty ? "Nothing changed since the last commit."
                                 : "Pick a file to read its diff.")
                .font(Typo.text(13)).foregroundStyle(Theme.tx3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector

    private var inspector: some View {
        let added = changes.reduce(0) { $0 + $1.added }
        let removed = changes.reduce(0) { $0 + $1.removed }
        return Inspector(width: 336) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Working tree")
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.accent)
                    Text(branch ?? "no branch")
                        .font(Typo.mono(11.5)).foregroundStyle(Theme.tx)
                    Spacer(minLength: 8)
                    Text("\(changes.count) file\(changes.count == 1 ? "" : "s")")
                        .font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                }
                HStack(spacing: 10) {
                    Text("+\(added)").font(Typo.mono(12)).foregroundStyle(Theme.green)
                    Text("−\(removed)").font(Typo.mono(12)).foregroundStyle(Theme.red)
                    Spacer(minLength: 0)
                }
                if let head {
                    Text("against \(head)")
                        .font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 15)

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("By file")
                ForEach(changes) { file in
                    Button { select(file.path) } label: {
                        HStack(spacing: 8) {
                            Text(file.name).font(Typo.mono(10.5))
                                .foregroundStyle(file.path == path ? Theme.tx : Theme.tx2)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text("+\(file.added)").font(Typo.mono(10)).foregroundStyle(Theme.green)
                            Text("−\(file.removed)").font(Typo.mono(10)).foregroundStyle(Theme.red)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Text("QA passes a task before the lead marks it done; the lead opens the PR and "
                 + "stops. Merging is yours.")
                .font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineSpacing(2)
        }
    }

    private func load() {
        guard let change else { return lines = [] }
        lines = GitChanges.diff(of: change, in: project.directory)
    }
}
