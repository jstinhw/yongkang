import SwiftUI

/// A rail for choosing what you are looking at — roadmap above, projects below — and the
/// rest of the window for the chosen project's tasks, laid out left to right in dependency
/// order: a task sits one lane right of everything it waits on, so the shape of the work is
/// the layout rather than a line of small print. Selecting a card dims what it has no
/// relationship with.
struct NotebookBoard: View {
    let cards: [NotebookCard]
    /// The project folder, which is what `repos:` paths are relative to.
    let directory: URL
    /// Tasks a still-open Engineering Lead session already has — shown as WIP and not
    /// pickable for a new batch.
    let assigned: Set<String>
    let showDone: Bool
    let open: (URL) -> Void
    let assign: ([NotebookCard]) -> Void
    let review: () -> Void
    let run: (NotebookCard) -> Void

    @State private var selected: Set<String> = []

    var body: some View {
        // ponytail: no tap-to-clear on the background. A container tap gesture sitting
        // under the cards is exactly what eats a click that should have selected one.
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    column("Roadmap", items(of: .roadmap))
                    Divider()
                    column("Projects", items(of: .project))
                }
                .frame(width: 240)
                Divider()
                lanes
            }
            Divider()
            assignBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Tasks are the only assignable kind — clicking a project does not enlist its work.
    private var picked: [NotebookCard] {
        NotebookIndex.ordered(NotebookIndex.visible(
            cards.filter { $0.kind == .task && selected.contains($0.id) }, showDone: showDone))
    }

    /// What actually gets shipped: the picks plus the unfinished work they wait on, minus
    /// anything a still-open lead session already has.
    private var batch: [NotebookCard] {
        NotebookIndex.withBlockers(picked, in: cards, excluding: assigned)
    }

    private var single: NotebookCard? {
        selected.count == 1 ? cards.first { selected.contains($0.id) } : nil
    }

    /// The one project the board is scoped to. Tasks outside it are not on screen, so they
    /// cannot be picked — a batch is one project's work plus whatever it waits on.
    private var scope: String? {
        NotebookIndex.visible(cards.filter { $0.kind == .project }, showDone: showDone)
            .first { selected.contains($0.id) }?.id
    }

    /// The scoped project's own card, so the lanes can open with its title and
    /// progress instead of a bare "Tasks" label — a project page, not just a filter.
    private var scopedProject: NotebookCard? {
        guard let scope else { return nil }
        return cards.first { $0.id == scope }
    }

    /// This project's tasks, and how many are done — the number Linear puts next to a
    /// project's name everywhere it's listed.
    private func progress(of project: NotebookCard) -> (done: Int, total: Int) {
        let tasks = cards.filter { $0.kind == .task && $0.project == project.id }
        return (tasks.filter { $0.status == "done" }.count, tasks.count)
    }

    /// The lanes' own header once a project is picked: title, status, and completion —
    /// a small project page rather than a generic "Tasks" list.
    private func projectHeader(_ project: NotebookCard) -> some View {
        let (done, total) = progress(of: project)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(project.title)
                .font(.title3.weight(.semibold))
            if !project.status.isEmpty { NotebookStyle.pill(project.status) }
            Spacer(minLength: 12)
            if total > 0 {
                Text("\(done)/\(total) done")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Always on screen, so the action is discoverable before anything is picked and a
    /// click that registers visibly changes something.
    private var assignBar: some View {
        HStack(spacing: 10) {
            if picked.isEmpty {
                Text(scope == nil ? "Click a project to see its tasks."
                                  : "Click task cards to pick them for an engineering lead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let pulled = batch.count - picked.count
                Text("\(picked.count) picked" + (pulled > 0 ? " · \(pulled) blocker\(pulled == 1 ? "" : "s") pulled in" : ""))
                    .font(.callout)
                Text(batch.map(\.id).joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            // Never disabled and never about the picks: this one asks what should be on the
            // board at all, which is the question an empty or stalled board most needs.
            Button("Product Review", systemImage: "sparkles", action: review)
            Button("Open File") { single.map { open($0.url) } }
                .disabled(single == nil)
            Button("Clear") { selected.removeAll() }
                .disabled(selected.isEmpty)
            Button("Assign to Engineering Lead") { assign(batch) }
                .buttonStyle(.borderedProminent)
                .disabled(batch.isEmpty)
        }
        .padding(12)
    }

    // MARK: - Task lanes

    /// Waves come off the whole task graph, then get filtered to the project. A task held
    /// up by another project's work keeps its lane, so it does not read as ready to start.
    private var waves: [[NotebookCard]] {
        guard let scope else { return [] }
        return NotebookIndex.waves(NotebookIndex.visible(cards.filter { $0.kind == .task },
                                                          showDone: showDone))
            .map { $0.filter { $0.project == scope } }
            .filter { !$0.isEmpty }
    }

    private var lanes: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project = scopedProject {
                projectHeader(project)
            } else {
                heading("Tasks", count: waves.reduce(0) { $0 + $1.count })
            }
            if scope == nil {
                placeholder("Pick a project on the left to see its tasks.")
            } else if waves.isEmpty {
                placeholder("This project has no tasks yet.")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(waves.enumerated()), id: \.offset) { index, wave in
                            if index > 0 { arrow }
                            lane(index: index, wave: wave)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A lane is a level, not a set of edges: its cards can all start once the lanes to the
    /// left are done. Which particular task holds one up is on the card itself.
    private func lane(index: Int, wave: [NotebookCard]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(index == 0 ? "READY" : "STEP \(index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(index == 0 ? Color.accentColor : .secondary)
                .padding(.bottom, 2)
            ForEach(wave) { view(of: $0) }
        }
        .frame(width: 260, alignment: .topLeading)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 34)
    }

    // MARK: - Rail

    private func column(_ title: String, _ items: [NotebookCard]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(title, count: items.count)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { card in view(of: card) }
                    if items.isEmpty { placeholder("Nothing here yet.") }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func items(of kind: EntryKind) -> [NotebookCard] {
        let items = cards.filter { $0.kind == kind }
        return NotebookIndex.ordered(kind == .project
            ? NotebookIndex.visible(items, showDone: showDone) : items)
    }

    private func heading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
    }

    // MARK: - Cards

    @ViewBuilder
    private func view(of card: NotebookCard) -> some View {
        if card.kind == .task && (assigned.contains(card.id) || card.status == "done") {
            // Already has a lead on it, or already shipped — not a Button, so it cannot be
            // picked into a batch that would just hand it out again.
            body(of: card).opacity(0.6)
        } else if card.kind == .project {
            // A Button, not a tap gesture: it consumes the click unambiguously and comes with
            // keyboard and accessibility behaviour a gesture does not.
            Button { selected = NotebookBoard.picking(card, in: cards, from: selected) } label: {
                projectCard(card)
            }
            .buttonStyle(.plain)
        } else {
            Button { selected = NotebookBoard.picking(card, in: cards, from: selected) } label: {
                body(of: card)
            }
            .buttonStyle(.plain)
        }
    }

    /// A project's own card design: a Linear-style status ring in place of a text pill,
    /// and a completion bar in place of the plain status word — the rail's projects are
    /// where "how far along is this" actually matters at a glance.
    private func projectCard(_ card: NotebookCard) -> some View {
        let (done, total) = progress(of: card)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NotebookStyle.statusRing(card.status, progress: total > 0 ? Double(done) / Double(total) : 0)
                Text(card.title)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                runButton(card)
            }
            Text(subtitle(of: card))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if total > 0 {
                HStack(spacing: 6) {
                    ProgressView(value: Double(done), total: Double(total))
                        .progressViewStyle(.linear)
                        .tint(NotebookStyle.color(of: card.status))
                    Text("\(done)/\(total)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            repos(of: card)
            if let waits = NotebookStyle.edge("waits on ", card.dependsOn, in: cards) { waits.font(.caption2) }
            if let blocks = NotebookStyle.edge("blocks ", NotebookStyle.dependents(of: card, in: cards), in: cards) { blocks.font(.caption2) }
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

    /// One project at a time: picking a project swaps the scope rather than adding to it,
    /// and drops the task picks that came with the old one. A pick that has just left the
    /// lanes must not stay in the batch, where nothing on screen would show it.
    static func picking(_ card: NotebookCard, in cards: [NotebookCard],
                        from selected: Set<String>) -> Set<String> {
        guard card.kind == .project else { return selected.symmetricDifference([card.id]) }
        let kept = selected.filter { id in cards.contains { $0.id == id && $0.kind == .roadmap } }
        return selected.contains(card.id) ? kept : kept.union([card.id])
    }

    /// Roadmap and task cards — projects get their own design in `projectCard`.
    private func body(of card: NotebookCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.title)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !card.status.isEmpty { NotebookStyle.pill(card.status) }
                if assigned.contains(card.id) { NotebookStyle.pill("wip") }
            }
            Text(subtitle(of: card))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let waits = NotebookStyle.edge("waits on ", card.dependsOn, in: cards) { waits.font(.caption2) }
            if let blocks = NotebookStyle.edge("blocks ", NotebookStyle.dependents(of: card, in: cards), in: cards) { blocks.font(.caption2) }
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

    /// Starting the project is a click on the project, not a menu somewhere else. Borderless
    /// inside the card's own Button so it takes the click rather than selecting the card.
    private func runButton(_ card: NotebookCard) -> some View {
        Button { run(card) } label: {
            Image(systemName: "play.fill").font(.caption2)
        }
        .buttonStyle(.borderless)
        .help("Run this project's services")
    }

    /// What the work touches, and whether it can be started. A repo that is not on disk
    /// yet — the usual state before anything is scaffolded — says so in orange rather than
    /// looking like a repo with nothing to run.
    private func repos(of card: NotebookCard) -> some View {
        let plan = Service.plan(for: card, in: directory)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(plan, id: \.repo) { step in
                let missing = !FileManager.default.fileExists(atPath: step.directory.path)
                HStack(spacing: 4) {
                    Image(systemName: missing ? "questionmark.folder" : "folder")
                    Text(step.repo)
                    Text(missing ? "not created yet" : summary(step.services))
                        .foregroundStyle(missing || step.services.allSatisfy { $0.command == nil }
                                        ? Color.orange : .secondary)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// One service reads as its command; several read as a count — the repo card is a
    /// summary, the preview tab is where each one gets its own line.
    private func summary(_ services: [Service.Runnable]) -> String {
        guard services.count > 1 else { return services.first?.command ?? "nothing to run" }
        let runnable = services.filter { $0.command != nil }.count
        return "\(services.count) services" + (runnable < services.count ? " (\(runnable) runnable)" : "")
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
            if let roadmap = card.roadmap { ids.insert(roadmap) }
        }
        ids.formUnion(cards.filter { $0.dependsOn.contains(where: selected.contains) }.map(\.id))
        ids.formUnion(cards.filter { selected.contains($0.project ?? "") }.map(\.id))
        ids.formUnion(cards.filter { selected.contains($0.roadmap ?? "") }.map(\.id))
        return ids
    }

    private func subtitle(of card: NotebookCard) -> String {
        var parts = [card.id]
        if let project = card.project, card.kind != .task { parts.append("in \(project)") }
        let notes = cards.filter { $0.kind == .memory && $0.project == card.id }.count
        if card.kind == .project, notes > 0 { parts.append("\(notes) memory") }
        return parts.joined(separator: " · ")
    }


}
