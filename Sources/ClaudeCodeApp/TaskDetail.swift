import SwiftUI

/// One task's own page — its checklist, its notes, where it sits in the graph — instead
/// of the raw Markdown file.
struct TaskDetail: View {
    let card: NotebookCard
    let cards: [NotebookCard]
    /// Whether a still-open Engineering Lead session already has this task.
    let assigned: Set<String>
    let open: (URL) -> Void
    let assign: ([NotebookCard]) -> Void

    @State private var content: [NotebookContent.Section] = []

    private var locked: Bool { assigned.contains(card.id) || card.status == "done" }
    private var project: NotebookCard? {
        card.project.flatMap { id in cards.first { $0.id == id && $0.kind == .project } }
    }
    private var batch: [NotebookCard] {
        NotebookIndex.withBlockers([card], in: cards, excluding: assigned)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !content.isEmpty {
                        NotebookContentView(sections: content, cards: cards)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actionBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: card.id) { load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                NotebookStyle.statusRing(card.status, progress: card.status == "active" ? 0.4 : 0, size: 18)
                Text(card.title)
                    .font(.title2.weight(.semibold))
                if !card.status.isEmpty { NotebookStyle.pill(card.status) }
                if assigned.contains(card.id) { NotebookStyle.pill("wip") }
                Spacer(minLength: 12)
                Button("Edit", systemImage: "pencil") { open(card.url) }
                    .buttonStyle(.borderless)
            }
            if let project {
                Text("in \(project.title)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let waits = NotebookStyle.edge("waits on ", card.dependsOn, in: cards) { waits.font(.caption) }
            if let blocks = NotebookStyle.edge("blocks ", NotebookStyle.dependents(of: card, in: cards), in: cards) {
                blocks.font(.caption)
            }
        }
    }

    private func load() {
        let text = (try? String(contentsOf: card.url, encoding: .utf8)) ?? ""
        content = NotebookContent.sections(NotebookIndex.body(text))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button("Open File") { open(card.url) }
            Button("Assign to Engineering Lead") { assign(batch) }
                .buttonStyle(.borderedProminent)
                .disabled(locked)
        }
        .padding(12)
    }

    private var status: String {
        if card.status == "done" { return "Done." }
        if assigned.contains(card.id) { return "Already assigned to an Engineering Lead." }
        let pulled = batch.count - 1
        return pulled > 0 ? "\(pulled) blocker\(pulled == 1 ? "" : "s") pulled in with it." : "Ready to assign."
    }
}
