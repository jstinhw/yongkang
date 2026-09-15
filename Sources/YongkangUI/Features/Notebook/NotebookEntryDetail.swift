import SwiftUI
import YongkangCore

/// The human view for notebook pages that do not need task/project-specific actions.
/// Raw Markdown remains one click away for direct edits and agent-written fields.
struct NotebookEntryDetail: View {
    let card: NotebookCard
    let cards: [NotebookCard]
    let open: (URL) -> Void

    @State private var content: [NotebookContent.Section] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !content.isEmpty {
                    NotebookContentView(sections: content, cards: cards)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(padding: 16)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .task(id: card.id) { load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.tx3)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.line2, lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title).font(Typo.display(21))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(card.id).font(Typo.mono(11)).foregroundStyle(Theme.tx3)
                        if !badge.isEmpty { NotebookStyle.pill(badge) }
                    }
                }
                Spacer(minLength: 12)
                Button {
                    open(card.url)
                } label: {
                    Label("Edit file", systemImage: "pencil")
                }
                .buttonStyle(.consoleGhost)
            }
            if !metadata.isEmpty {
                Text(metadata.joined(separator: " · "))
                    .font(Typo.text(11.5))
                    .foregroundStyle(Theme.tx3)
            }
        }
    }

    private var badge: String {
        if card.kind == .run { return card.result }
        if card.kind == .memory { return card.memoryType }
        return card.status
    }

    private var metadata: [String] {
        var values = [card.kind.displayName]
        if let subject = card.subject { values.append("about \(title(for: subject))") }
        if let project = card.project, project != card.subject { values.append("in \(title(for: project))") }
        if let roadmap = card.roadmap { values.append("for \(title(for: roadmap))") }
        return values
    }

    private var icon: String {
        switch card.kind {
        case .roadmap: return "map"
        case .memory: return "brain"
        case .run: return "clock.arrow.circlepath"
        case .project: return "shippingbox"
        case .task: return "checkmark.circle"
        }
    }

    private func title(for id: String) -> String {
        cards.first { $0.id == id }?.title ?? id
    }

    private func load() {
        let text = (try? String(contentsOf: card.url, encoding: .utf8)) ?? ""
        content = NotebookContent.sections(NotebookIndex.body(text))
    }
}
