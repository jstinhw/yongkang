import SwiftUI

/// Roadmap → projects → tasks in three columns, ordered so nothing appears before what
/// it depends on. Selecting a card dims everything it has no relationship with.
struct NotebookBoard: View {
    let cards: [NotebookCard]
    let open: (URL) -> Void
    let assign: ([NotebookCard]) -> Void

    @State private var selected: Set<String> = []

    var body: some View {
        // ponytail: no tap-to-clear on the background. A container tap gesture sitting
        // under the cards is exactly what eats a click that should have selected one.
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                column("Roadmap", .roadmap)
                Divider()
                column("Projects", .project)
                Divider()
                column("Tasks", .task)
            }
            Divider()
            assignBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Tasks are the only assignable kind — clicking a project does not enlist its work.
    private var picked: [NotebookCard] {
        ordered(cards.filter { $0.kind == .task && selected.contains($0.id) })
    }

    private var single: NotebookCard? {
        selected.count == 1 ? cards.first { selected.contains($0.id) } : nil
    }

    /// Always on screen, so the action is discoverable before anything is picked and a
    /// click that registers visibly changes something.
    private var assignBar: some View {
        HStack(spacing: 10) {
            if picked.isEmpty {
                Text("Click task cards to pick them for an engineering lead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(picked.count) task\(picked.count == 1 ? "" : "s") picked")
                    .font(.callout)
                Text(picked.map(\.id).joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            Button("Open File") { single.map { open($0.url) } }
                .disabled(single == nil)
            Button("Clear") { selected.removeAll() }
                .disabled(selected.isEmpty)
            Button("Assign to Engineering Lead") { assign(picked) }
                .buttonStyle(.borderedProminent)
                .disabled(picked.isEmpty)
        }
        .padding(12)
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
        // A Button, not a tap gesture: it consumes the click unambiguously and comes with
        // keyboard and accessibility behaviour a gesture does not.
        Button { selected.formSymmetricDifference([card.id]) } label: {
            body(of: card)
        }
        .buttonStyle(.plain)
    }

    private func body(of card: NotebookCard) -> some View {
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected.contains(card.id) ? Color.accentColor : .clear, lineWidth: 2)
        )
        .opacity(selected.isEmpty || related.contains(card.id) ? 1 : 0.3)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Relationships

    /// What the picked cards touch: what they wait on, what waits on them, and the
    /// project they belong to (or, for a project, everything filed under it).
    private var related: Set<String> {
        guard !selected.isEmpty else { return [] }
        var ids = selected
        for card in cards where selected.contains(card.id) {
            ids.formUnion(card.dependsOn)
            if let project = card.project { ids.insert(project) }
        }
        ids.formUnion(cards.filter { $0.dependsOn.contains(where: selected.contains) }.map(\.id))
        ids.formUnion(cards.filter { selected.contains($0.project ?? "") }.map(\.id))
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
