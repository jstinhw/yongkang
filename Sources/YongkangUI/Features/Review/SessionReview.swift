import SwiftUI
import YongkangCore

/// A session's result: the review of each task it holds, one at a time, because approving
/// commits one task. Opens on the first of them waiting for the user; a strip of the chain's
/// tasks picks another when there is more than one.
package struct SessionReview<Review: View>: View {
    let session: CodeSession
    let summary: ChangeSummary
    /// The review page for one task, built by the window so it carries the same actions as
    /// the Review section's own.
    let review: (SummaryTask) -> Review

    @State private var picked: String?

    package init(session: CodeSession, summary: ChangeSummary, @ViewBuilder review: @escaping (SummaryTask) -> Review) {
        self.session = session
        self.summary = summary
        self.review = review
    }

    /// In the order the session was handed them, which is the chain's build order.
    private var tasks: [SummaryTask] {
        session.taskIDs.compactMap { id in summary.tasks.first { $0.id == id } }
    }

    private var shown: SummaryTask? {
        tasks.first { $0.id == picked } ?? summary.waiting(for: session).first ?? tasks.first
    }

    package var body: some View {
        VStack(spacing: 0) {
            if tasks.count > 1 { strip }
            if let shown {
                review(shown).id(shown.id)
            } else {
                Text("None of this session’s tasks is in the notebook any more.")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SectionLabel("Tasks").padding(.trailing, 6)
                ForEach(tasks) { tab($0) }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func tab(_ task: SummaryTask) -> some View {
        let selected = task.id == shown?.id
        let (state, tint) = Self.state(of: task)
        return Button {
            picked = task.id
        } label: {
            HStack(spacing: 8) {
                NotebookStyle.statusRing(task.status, progress: 0, size: 12)
                Text(task.title).font(Typography.body).foregroundStyle(selected ? Theme.tx : Theme.tx2)
                    .lineLimit(1)
                NotebookStyle.pill(state, tint)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.raised : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.hairline : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What a tab says about its task: waiting on the user, finished and committed, or
    /// still with the agent.
    private static func state(of task: SummaryTask) -> (String, Color) {
        if task.done { return task.files.isEmpty ? ("done", Theme.tx3) : ("review", Theme.green) }
        return (task.status.isEmpty ? "queued" : task.status, Theme.accent)
    }
}
