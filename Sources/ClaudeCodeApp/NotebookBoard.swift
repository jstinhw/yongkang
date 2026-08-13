import SwiftUI

/// Roadmap → projects → tasks in three columns, ordered so nothing appears before what
/// it depends on. Selecting a card dims everything it has no relationship with.
struct NotebookBoard: View {
    let cards: [NotebookCard]
    let open: (URL) -> Void

    @State private var selected: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column("Roadmap", .roadmap)
            Divider()
            column("Projects", .project)
            Divider()
            column("Tasks", .task)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onTapGesture { selected = nil }
    }

    // MARK: - Columns

    private func column(_ title: String, _ kind: EntryKind) -> some View {
        let items = ordered(cards.filter { $0.kind == kind })
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { card in view(of: card) }
                    if items.isEmpty {
                        Text("Nothing here yet.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func view(of card: NotebookCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.title)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !card.status.isEmpty { pill(card.status) }
            }
            Text(subtitle(of: card))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let blockers = blockers(of: card) {
                blockers.font(.caption2)
            }
            if selected == card.id {
                Button("Open File") { open(card.url) }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected == card.id ? Color.accentColor : .clear)
        )
        .opacity(selected == nil || related.contains(card.id) ? 1 : 0.3)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { selected = selected == card.id ? nil : card.id }
    }

    // MARK: - Relationships

    /// What the selected card touches: what it waits on, what waits on it, and the
    /// project it belongs to (or, for a project, everything filed under it).
    private var related: Set<String> {
        guard let selected, let card = cards.first(where: { $0.id == selected }) else { return [] }
        var ids: Set<String> = [selected]
        ids.formUnion(card.dependsOn)
        ids.formUnion(cards.filter { $0.dependsOn.contains(selected) }.map(\.id))
        ids.formUnion(cards.filter { $0.project == selected }.map(\.id))
        if let project = card.project { ids.insert(project) }
        return ids
    }

    private func subtitle(of card: NotebookCard) -> String {
        var parts = [card.id]
        if let project = card.project { parts.append("in \(project)") }
        let notes = cards.filter { $0.kind == .memory && $0.project == card.id }.count
        if card.kind == .project, notes > 0 { parts.append("\(notes) memory") }
        return parts.joined(separator: " · ")
    }

    /// Unknown ids show in orange — a typo in `depends_on` is otherwise invisible.
    private func blockers(of card: NotebookCard) -> Text? {
        guard !card.dependsOn.isEmpty else { return nil }
        return card.dependsOn.reduce(Text("waits on ").foregroundColor(.secondary)) { text, id in
            let known = cards.contains { $0.id == id }
            let separator = id == card.dependsOn.first ? "" : ", "
            return text + Text(separator).foregroundColor(.secondary)
                + Text(known ? id : "\(id)?").foregroundColor(known ? .secondary : .orange)
        }
    }

    // ponytail: Kahn's with ties left in file order, O(n²) over a column of cards. A
    // cycle stops the sort and appends the rest rather than dropping anything.
    private func ordered(_ subset: [NotebookCard]) -> [NotebookCard] {
        let present = Set(subset.map(\.id))
        var remaining = subset
        var placed: Set<String> = []
        var result: [NotebookCard] = []

        while !remaining.isEmpty {
            let ready = remaining.filter { $0.dependsOn.filter(present.contains).allSatisfy(placed.contains) }
            guard !ready.isEmpty else { return result + remaining }
            result.append(contentsOf: ready)
            placed.formUnion(ready.map(\.id))
            let readyIDs = Set(ready.map(\.id))
            remaining.removeAll { readyIDs.contains($0.id) }
        }
        return result
    }

    private func pill(_ status: String) -> some View {
        Text(status)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color(of: status))
            .background(Capsule().fill(color(of: status).opacity(0.15)))
    }

    private func color(of status: String) -> Color {
        switch status {
        case "done": return .green
        case "active": return .blue
        case "blocked": return .orange
        default: return .gray
        }
    }
}
