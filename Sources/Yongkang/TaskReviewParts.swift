import SwiftUI

/// One agent's part in a task, in its own words: the work record's `## Result` when it
/// wrote one, its one-line report when it did not, and — on a later attempt — the user's
/// comments the lead quoted for it, so a reply reads under the question it answers.
struct WorkReport: View {
    let work: LeadWork
    /// The roster name, empty when no roster member runs this skill.
    let name: String
    let cards: [NotebookCard]
    /// Nil for QA, which owns no files; otherwise a file opens its diff.
    let openFile: ((String) -> Void)?

    private var isQA: Bool { work.skill.lowercased().contains("qa") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoleTile(role: work.skill, size: 22)
                if !name.isEmpty { Text(name).font(Typo.text(13, .medium)).foregroundStyle(Theme.tx) }
                Text(work.skill).font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                Spacer(minLength: 8)
                if !work.model.isEmpty { NotebookStyle.chip(work.model, mono: true) }
                if let minutes = work.elapsedMinutes() {
                    Text(minutes < 1 ? "\(Int(minutes * 60))s" : "\(Int(minutes.rounded())) min")
                        .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                }
                verdict
            }
            Text(work.title).font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
            if !work.changeRequest.isEmpty { asked }
            if !work.result.isEmpty {
                NotebookContentView(sections: NotebookContent.sections(work.result), cards: cards)
            } else if !work.report.isEmpty {
                Text(work.report).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing reported back yet.").font(Typo.text(12)).foregroundStyle(Theme.tx3)
            }
            if let openFile, !work.paths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(work.paths, id: \.self) { path in
                        Button {
                            openFile(path)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").font(.system(size: 10))
                                Text(path).font(Typo.mono(10.5)).lineLimit(1).truncationMode(.head)
                            }
                            .foregroundStyle(Theme.tx2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open the diff")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 10, padding: 12, fill: Theme.raised)
    }

    /// QA's state is a verdict on someone else's work, so it reads as pass or fail; a
    /// builder's is just where its own work stands.
    @ViewBuilder private var verdict: some View {
        if isQA && work.state == "done" {
            NotebookStyle.pill("pass", Theme.green)
        } else if isQA && work.state == "failed" {
            NotebookStyle.pill("fail", Theme.red)
        } else {
            NotebookStyle.pill(work.state, NotebookStyle.color(of: work.state), live: work.runtimeRunning == true)
        }
    }

    private var asked: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("You asked")
            NotebookContentView(sections: NotebookContent.sections(work.changeRequest), cards: cards)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 9, padding: 10, border: Theme.amber.opacity(0.24), fill: Theme.amber.opacity(0.05))
    }
}

/// Everything the user wants the agents to change, before it is sent: the comments left on
/// diff lines, and a note for anything that is not about one line.
struct FeedbackCard: View {
    @Binding var draft: ReviewDraft
    let openFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(
                "Feedback for the agents",
                trailing: draft.comments.isEmpty ? nil : "\(draft.comments.count) on lines")
            ForEach(draft.comments) { comment in
                HStack(alignment: .top, spacing: 9) {
                    VStack(alignment: .leading, spacing: 3) {
                        Button {
                            openFile(comment.path)
                        } label: {
                            Text("\(comment.path):\(comment.line)").font(Typo.mono(10.5)).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        Text(comment.text).font(Typo.text(12)).foregroundStyle(Theme.tx)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        draft.comments.removeAll { $0.id == comment.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10))
                    }
                    .buttonStyle(.consoleGhost)
                    .help("Delete this comment")
                }
                .cardSurface(radius: 9, padding: 10, fill: Theme.raised)
            }
            TextField("Anything else for the agents — sent with your line comments", text: $draft.note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .font(Typo.text(12.5))
                .foregroundStyle(Theme.tx)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
            Text("To comment on code, open a file under Changes by area and click a line.")
                .font(Typo.text(11)).foregroundStyle(Theme.tx3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }
}

/// The two ways a review ends, on the task page and on each of its diffs alike. Only one of
/// them is the primary: approving, until the user has written something for the agents —
/// then sending it, because approving would drop what they wrote.
struct TaskReviewBar: View {
    let task: SummaryTask
    let draft: ReviewDraft
    let approve: (String) -> String?
    let requestChanges: () -> Void

    @State private var message = ""
    @State private var failure = ""

    var body: some View {
        ActionBar {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(Theme.tx3)
            TextField("Commit message", text: $message)
                .textFieldStyle(.plain)
                .font(Typo.mono(11.5))
                .foregroundStyle(Theme.tx)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
            if !failure.isEmpty {
                Text(failure).font(Typo.mono(10.5)).foregroundStyle(Theme.red)
                    .lineLimit(2).frame(maxWidth: 260, alignment: .leading)
            }
            if draft.isEmpty {
                Button(action: requestChanges) { Label("Request changes", systemImage: "text.bubble") }
                    .buttonStyle(.console)
                    .disabled(true)
                    .help("Comment on a line or write a note first")
                approveButton.buttonStyle(.consolePrimary)
            } else {
                approveButton.buttonStyle(.console)
                    .help("Commits without sending your feedback, which is then discarded")
                Button(action: requestChanges) {
                    Label(
                        "Request changes · \(draft.comments.count + (draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1))",
                        systemImage: "text.bubble")
                }
                .buttonStyle(.consolePrimary)
            }
        }
        .task(id: task.id) {
            message = task.title
            failure = ""
        }
    }

    private var approveButton: some View {
        Button {
            failure = approve(message) ?? ""
        } label: {
            Label("Approve and commit", systemImage: "checkmark.seal")
        }
        .disabled(
            !task.done || task.commitPaths.isEmpty
                || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
