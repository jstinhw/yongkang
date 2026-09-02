import SwiftUI

/// The build order. Every task that could be worked on, laid out left to right in
/// dependency order — a task sits one lane right of everything it waits on — so the shape
/// of the work is the layout rather than a line of small print.
///
/// The roadmap and projects that used to share this screen now live in the list column
/// beside it, which leaves the board to do one job: pick the batch and hand it to a lead.
struct NotebookBoard: View {
    let cards: [NotebookCard]
    /// Tasks a still-open Engineering Lead session already has — shown as WIP and not
    /// pickable for a new batch.
    let assigned: Set<String>
    let showDone: Bool
    let assign: ([NotebookCard]) -> Void
    let review: () -> Void
    /// Opens a card's own page — separate from picking it, which the rest of the card does.
    let openCard: (NotebookCard) -> Void

    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if waves.isEmpty {
                empty
            } else {
                // Nested single-axis scrolls rather than one two-axis ScrollView: a
                // two-axis one centres content smaller than its viewport, which floats the
                // lanes in the middle of the canvas instead of starting them at the top.
                ScrollView(.vertical) {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(waves.enumerated()), id: \.offset) { index, wave in
                                if index > 0 { arrow }
                                lane(index: index, wave: wave)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DotGrid())
            }
            assignBar
        }
        .background(Theme.bg)
    }

    // MARK: - The graph

    private var tasks: [NotebookCard] {
        NotebookIndex.visible(cards.filter { $0.kind == .task }, showDone: showDone)
    }

    /// Waves come off the whole task graph: a lane is a level, not a set of edges — its
    /// cards can all start once the lanes to the left are done.
    private var waves: [[NotebookCard]] {
        NotebookIndex.waves(tasks).filter { !$0.isEmpty }
    }

    private var picked: [NotebookCard] {
        NotebookIndex.ordered(tasks.filter { selected.contains($0.id) })
    }

    /// What actually gets shipped: the picks plus the unfinished work they wait on, minus
    /// anything a still-open lead session already has.
    private var batch: [NotebookCard] {
        NotebookIndex.withBlockers(picked, in: cards, excluding: assigned)
    }

    /// What the picked cards touch: what they wait on, and what waits on them.
    private var related: Set<String> {
        guard !selected.isEmpty else { return [] }
        var ids = selected
        for card in cards where selected.contains(card.id) {
            ids.formUnion(card.dependsOn)
        }
        ids.formUnion(cards.filter { $0.dependsOn.contains(where: selected.contains) }.map(\.id))
        return ids
    }

    // MARK: - Lanes

    private func lane(index: Int, wave: [NotebookCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(index == 0 ? "READY" : "STEP \(index + 1)")
                    .font(Typo.section).tracking(1.5)
                    .foregroundStyle(index == 0 ? Theme.accent : Theme.tx3)
                Text("\(wave.count)").font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            }
            .padding(.bottom, 2)
            ForEach(wave) { card(of: $0) }
        }
        .frame(width: 266, alignment: .topLeading)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13))
            .foregroundStyle(Theme.tx4)
            .frame(width: 44)
            .padding(.top, 52)
    }

    // MARK: - Cards

    @ViewBuilder private func card(of card: NotebookCard) -> some View {
        let locked = assigned.contains(card.id) || card.status == "done"
        if locked {
            // Already has a lead on it, or already shipped — not pickable into a batch that
            // would just hand it out again.
            body(of: card).opacity(0.6)
        } else {
            Button { selected = NotebookBoard.picking(card, from: selected) } label: {
                body(of: card)
            }
            .buttonStyle(.plain)
        }
    }

    private func body(of card: NotebookCard) -> some View {
        let isPicked = selected.contains(card.id)
        let project = card.project.flatMap { id in cards.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                NotebookStyle.statusRing(card.status, progress: card.status == "active" ? 0.55 : 0,
                                         size: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(Typo.text(12.5))
                        .foregroundStyle(Theme.tx)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Text(card.id).font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { openCard(card) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tx3)
                }
                .buttonStyle(.borderless)
                .help("Open this task's page")
            }
            HStack(spacing: 6) {
                if !card.status.isEmpty { NotebookStyle.pill(card.status) }
                if assigned.contains(card.id) { NotebookStyle.pill("wip") }
                if let project { NotebookStyle.chip(project.title) }
            }
            .padding(.top, 10)
            if let waits = NotebookStyle.edge("waits on ", card.dependsOn, in: cards) {
                waits.font(Typo.mono(10)).padding(.top, 9)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(isPicked ? Theme.accent : Theme.line2, lineWidth: isPicked ? 1.5 : 1))
        .shadow(color: isPicked ? Theme.accent.opacity(0.25) : .clear, radius: 12, y: 4)
        .opacity(selected.isEmpty || related.contains(card.id) ? 1 : 0.32)
        .contentShape(RoundedRectangle(cornerRadius: 11))
    }

    /// Picking is a plain toggle: the board holds one kind of card now, and every one of
    /// them is a candidate for the same batch.
    static func picking(_ card: NotebookCard, from selected: Set<String>) -> Set<String> {
        selected.symmetricDifference([card.id])
    }

    // MARK: - Assign

    private var assignBar: some View {
        ActionBar {
            if picked.isEmpty {
                Text("Click task cards to pick them for an engineering lead.")
                    .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
            } else {
                let pulled = batch.count - picked.count
                Text("\(picked.count) picked").font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                if pulled > 0 {
                    Text("· \(pulled) blocker\(pulled == 1 ? "" : "s") pulled in")
                        .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
                }
                Text(batch.map(\.id).joined(separator: " → "))
                    .font(Typo.mono(11)).foregroundStyle(Theme.tx3).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Clear") { selected.removeAll() }
                .buttonStyle(.consoleGhost)
                .disabled(selected.isEmpty)
            // Never disabled and never about the picks: this one asks what should be on the
            // board at all, which is the question an empty or stalled board most needs.
            Button { review() } label: { Label("Product review", systemImage: "sparkles") }
                .buttonStyle(.console)
            Button { assign(batch) } label: {
                Label("Assign to Engineering Lead", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(.consolePrimary)
            .disabled(batch.isEmpty)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash").font(.system(size: 22))
                .foregroundStyle(Theme.tx4)
            Text(cards.contains { $0.kind == .task } ? "Every task here is done."
                                                     : "No tasks yet — Product writes them.")
                .font(Typo.text(13)).foregroundStyle(Theme.tx3)
            Button { review() } label: { Label("Product review", systemImage: "sparkles") }
                .buttonStyle(.console)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGrid())
    }
}

/// The board's ground: a dot grid, so the lanes read as a canvas rather than a table.
struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            let dot = Color(hex: 0x1A202A)
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                 with: .color(dot))
                    x += step
                }
                y += step
            }
        }
        .background(Theme.bg)
    }
}
