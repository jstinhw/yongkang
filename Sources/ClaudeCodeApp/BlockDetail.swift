import SwiftUI

/// What is being asked of the user, and the button that starts doing it. The body of a
/// block is written as a checklist by whoever hit the gate, so it renders exactly like a
/// task page — the difference is the action bar: this one starts a session whose whole
/// job is walking the user through it and then releasing the agent that is waiting.
struct BlockDetail: View {
    let block: UserBlock
    let cards: [NotebookCard]
    /// The session that is waiting on this, if it is still running.
    let waiting: CodeSession?
    let start: () -> Void
    let resolve: () -> Void

    @State private var content: [NotebookContent.Section] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !content.isEmpty {
                        NotebookContentView(sections: content, cards: cards)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actionBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: block.id) { load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: block.waiting
                      ? (block.isProposal ? "lightbulb.fill" : "hand.raised.fill")
                      : "checkmark.circle.fill")
                    .foregroundStyle(block.waiting ? Color.orange : .green)
                Text(block.title).font(.title2.weight(.semibold))
                NotebookStyle.pill(block.waiting
                                   ? (block.isProposal ? "needs your review" : "waiting on you")
                                   : "done")
                Spacer(minLength: 12)
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !block.resolution.isEmpty {
                Text(block.resolution).font(.callout)
            }
            if let link = block.link {
                Link(link.absoluteString, destination: link).font(.caption)
            }
        }
    }

    private var subtitle: String {
        let parent = block.task.flatMap { id in cards.first { $0.id == id } }
        if block.isProposal {
            let lead = block.waiting ? "Product proposes this" : "Built out"
            return parent.map { "\(lead) — advances \($0.title)" } ?? lead
        }
        let who = waiting.map { "\($0.title) is waiting" } ?? "Nothing is waiting on it any more"
        return parent.map { "\(who) — holds up \($0.title)" } ?? who
    }

    private func load() {
        let text = (try? String(contentsOf: block.url, encoding: .utf8)) ?? ""
        content = NotebookContent.sections(NotebookIndex.body(text))
    }

    private var footer: String {
        guard block.waiting else { return "Cleared." }
        return block.isProposal
            ? "Approving writes the project and its tasks onto the board. Nothing is assigned yet."
            : "An engineer will explain this first, then walk you through it one step at a time."
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(footer)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button(block.isProposal ? "Dismiss" : "Mark Resolved", action: resolve)
                .disabled(!block.waiting)
            Button(block.isProposal ? "Approve" : "Do It Now",
                   systemImage: block.isProposal ? "checkmark" : "play.fill", action: start)
                .buttonStyle(.borderedProminent)
                .disabled(!block.waiting)
        }
        .padding(12)
    }
}
