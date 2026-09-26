import SwiftUI
import YongkangCore

/// One agent's part in a task, in its own words: the work record's `## Result` when it
/// wrote one, and its one-line report when it did not. What the user asked for on a later
/// attempt is read in Feedback, beside the agent's answer to it.
struct WorkReport: View {
    let work: LeadWork
    /// The roster name, empty when no roster member runs this skill.
    let name: String
    let cards: [NotebookCard]
    /// A file opens its diff.
    let openFile: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoleTile(role: work.skill.isEmpty ? "work" : work.skill, size: 22)
                if !name.isEmpty { Text(name).font(Typography.body(.medium)).foregroundStyle(Theme.tx) }
                Text(work.skill).font(Typography.mono).foregroundStyle(Theme.tx3)
                Spacer(minLength: 8)
                if !work.model.isEmpty { NotebookStyle.chip(work.model, mono: true) }
                if let minutes = work.elapsedMinutes() {
                    Text(minutes < 1 ? "\(Int(minutes * 60))s" : "\(Int(minutes.rounded())) min")
                        .font(Typography.mono).foregroundStyle(Theme.tx3)
                }
                NotebookStyle.pill(work.state, NotebookStyle.color(of: work.state), live: work.runtimeRunning == true)
            }
            Text(work.title).font(Typography.body).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
            if !work.result.isEmpty {
                NotebookContentView(sections: NotebookContent.sections(work.result), cards: cards)
            } else if !work.report.isEmpty {
                Text(work.report).font(Typography.body).foregroundStyle(Theme.tx2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing reported back yet.").font(Typography.body).foregroundStyle(Theme.tx3)
            }
            if let openFile, !work.paths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(work.paths, id: \.self) { path in
                        Button {
                            openFile(path)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").font(.system(size: 10))
                                Text(path).font(Typography.mono).lineLimit(1).truncationMode(.head)
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
}

/// Something only the user can do for this task, with the block's own instructions read here
/// on the review rather than one click away in Blocks. The block's page keeps the rest — a
/// demo's approval, marking a block done.
struct NeedsYouCard: View {
    let block: UserBlock
    let cards: [NotebookCard]
    let open: (UserBlock) -> Void
    let start: (UserBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: block.isDemo ? "rectangle.on.rectangle" : "hand.raised.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.amber)
                SectionLabel("Needs you", trailing: NotebookFormat.relativePath(block.url))
            }
            Text(block.title).font(Typography.headline).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
            if !block.action.isEmpty {
                Text(block.action).font(Typography.body).foregroundStyle(Theme.prose)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NotebookContentView(sections: NotebookContent.sections(block.brief), cards: cards)
            HStack(spacing: 8) {
                if block.isDemo {
                    Button("Open the demo") { open(block) }.buttonStyle(.consolePrimary)
                } else {
                    Button("Walk me through it") { start(block) }.buttonStyle(.consolePrimary)
                    Button("Open the block") { open(block) }.buttonStyle(.console)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15, border: Theme.amber.opacity(0.4), fill: Theme.amber.opacity(0.05))
    }
}

/// The review's conversation with the agent: each earlier round — what the user asked and
/// what the agent said it did about it — then what goes in the next one, the comments left on
/// diff lines and a note for anything that is not about one line.
struct FeedbackCard: View {
    @Binding var draft: ReviewDraft
    /// The attempts that answered a change request, oldest first.
    let history: [LeadWork]
    let cards: [NotebookCard]
    let openFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(
                "Feedback",
                trailing: draft.comments.isEmpty ? nil : "\(draft.comments.count) on lines")
            ForEach(history) { round($0) }
            ForEach(draft.comments) { comment in
                HStack(alignment: .top, spacing: 9) {
                    VStack(alignment: .leading, spacing: 3) {
                        Button {
                            openFile(comment.path)
                        } label: {
                            Text("\(comment.path):\(comment.line)").font(Typography.mono).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        Text(comment.text).font(Typography.body).foregroundStyle(Theme.tx)
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
                    .accessibilityLabel("Delete the comment on \(comment.path) line \(comment.line)")
                }
                .cardSurface(radius: 9, padding: 10, fill: Theme.raised)
            }
            TextField("Anything else for the agents — sent with your line comments", text: $draft.note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .font(Typography.body)
                .foregroundStyle(Theme.tx)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
            Text("To comment on code, unfold a file under Code changes and click a line.")
                .font(Typography.caption).foregroundStyle(Theme.tx3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private func round(_ work: LeadWork) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            speaker("You asked", Theme.amber) {
                NotebookContentView(sections: NotebookContent.sections(work.changeRequest), cards: cards)
            }
            speaker("Agent", Theme.accent) {
                if !work.report.isEmpty {
                    Text(work.report).font(Typography.body).foregroundStyle(Theme.prose)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !work.result.isEmpty {
                    NotebookContentView(sections: NotebookContent.sections(work.result), cards: cards)
                } else {
                    Text("No answer filed yet.").font(Typography.body).foregroundStyle(Theme.tx3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 9, padding: 10, fill: Theme.well)
    }

    private func speaker<Content: View>(
        _ name: String, _ tint: Color, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(Typography.caption(.semibold)).foregroundStyle(tint).frame(width: 64, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The two ways a review ends, on the task page and on each of its diffs alike. Only one of
/// them is the primary: approving, until the user has written something for the agents —
/// then sending it, because approving would drop what they wrote.
struct TaskReviewBar: View {
    let task: SummaryTask
    let draft: ReviewDraft
    let approve: (String) async -> String?
    let requestChanges: () -> Void
    /// Asks, then reverts this task's work and hands the task back to be done again.
    let discard: () -> Void

    @State private var message = ""
    @State private var failure = ""
    /// While git commits, so a second press doesn't start a second commit behind it.
    @State private var committing = false

    var body: some View {
        ActionBar {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(Theme.tx3)
            TextField("Commit message", text: $message)
                .textFieldStyle(.plain)
                .font(Typography.code)
                .foregroundStyle(Theme.tx)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
            if !failure.isEmpty {
                Text(failure).font(Typography.mono).foregroundStyle(Theme.red)
                    .lineLimit(2).frame(maxWidth: 260, alignment: .leading)
            }
            Button(action: discard) { Label("Discard and rerun", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.console)
                .disabled(committing || !task.done || task.discardPaths.isEmpty)
                .help("Revert this task's changes and have an agent start it over")
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
            committing = true
            Task {
                failure = await approve(message) ?? ""
                committing = false
            }
        } label: {
            Label("Approve and commit", systemImage: "checkmark.seal")
        }
        .disabled(
            committing || !task.done || task.commitPaths.isEmpty
                || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
