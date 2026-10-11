import SwiftUI
import YongkangCore

/// A work session's Result: the review of each task it did — the same page a task's review
/// opens on everywhere else, so the two cannot drift apart. A session that did several picks between them along
/// the top, in the order it was handed them.
struct SessionReviews<Review: View>: View {
    /// Never empty: a session with no result shows the page it drew instead.
    let tasks: [SummaryTask]
    @ViewBuilder let review: (SummaryTask) -> Review

    @State private var picked: String?

    var body: some View {
        let current = tasks.first { $0.id == picked } ?? tasks[0]
        VStack(spacing: 0) {
            if tasks.count > 1 {
                HStack(spacing: 6) {
                    ForEach(tasks) { task in
                        Button(task.title) { picked = task.id }
                            .buttonStyle(.plain)
                            .font(Typography.body(task.id == current.id ? .semibold : .regular))
                            .foregroundStyle(task.id == current.id ? Theme.tx : Theme.tx2)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7).fill(task.id == current.id ? Theme.raised : .clear)
                            )
                            .accessibilityAddTraits(task.id == current.id ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Theme.bg)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            review(current).id(current.id)
        }
    }
}
