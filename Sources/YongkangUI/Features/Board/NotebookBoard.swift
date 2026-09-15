import AppKit
import SwiftUI
import YongkangCore

/// The build order, one column per project, read downwards. A task sits under everything
/// it waits on, so position *is* the dependency and no card has to spell it out.
///
/// The screen this replaced laid the same graph out as dependency waves running left to
/// right, which turned two straight chains into seven lanes and pushed four of them off
/// the right edge. Columns are bounded by the number of projects instead of by the length
/// of the longest chain, so nothing scrolls sideways.
///
/// The other half of the tidying is that detail is spent where it is worth something:
/// full cards only at the live edge of each chain — what is being designed, what is
/// waiting on you, what an agent is on, what could start next — and one line each for
/// work that is finished or still queued behind something.
package struct NotebookBoard: View {
    let cards: [NotebookCard]
    /// Open demos, which is how a task says a designer is waiting on the user.
    let blocks: [UserBlock]
    /// Tasks a still-open Engineering Lead session already has — shown as WIP and not
    /// pickable for a new batch.
    let assigned: Set<String>
    let showDone: Bool
    let assign: ([NotebookCard]) -> Void
    let review: () -> Void
    /// Opens a card's own page — separate from picking it, which the rest of the card does.
    let openCard: (NotebookCard) -> Void
    /// Opens the demo waiting on a task, which is the whole point of the gate.
    let openDemo: (UserBlock) -> Void
    /// Sends a task to the Trash. Off for one a lead already has.
    let remove: (NotebookCard) -> Void

    @State private var selected: Set<String> = []

    package init(
        cards: [NotebookCard],
        blocks: [UserBlock],
        assigned: Set<String>,
        showDone: Bool,
        assign: @escaping ([NotebookCard]) -> Void,
        review: @escaping () -> Void,
        openCard: @escaping (NotebookCard) -> Void,
        openDemo: @escaping (UserBlock) -> Void,
        remove: @escaping (NotebookCard) -> Void
    ) {
        self.cards = cards
        self.blocks = blocks
        self.assigned = assigned
        self.showDone = showDone
        self.assign = assign
        self.review = review
        self.openCard = openCard
        self.openDemo = openDemo
        self.remove = remove
    }

    package var body: some View {
        GeometryReader { geometry in
            // Below this the window cannot carry a fourth column: the inspector folds into
            // the board rather than squeezing the chains into a strip. Same threshold the
            // lead's board uses, so the two screens fold at the same drag.
            let narrow = geometry.size.width < 950
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if chains.isEmpty {
                        empty
                    } else {
                        board(narrow: narrow)
                    }
                    if !narrow {
                        BoardInspector(
                            demos: demos, cards: cards, batch: batch,
                            picked: Set(picked.map(\.id)), openDemo: openDemo)
                    }
                }
                assignBar
            }
        }
        .background(Theme.bg)
    }

    private func board(narrow: Bool) -> some View {
        // Worked out once per pass rather than per card: `batch` walks the whole graph,
        // and every row asks whether it is in it.
        let inBatch = Set(batch.map(\.id))
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                if narrow {
                    DisclosureGroup("The batch, and what is waiting on you") {
                        BoardInspector(
                            demos: demos, cards: cards, batch: batch,
                            picked: Set(picked.map(\.id)), openDemo: openDemo,
                            inline: true)
                    }
                    .font(Typo.text(12)).tint(Theme.tx2).cardSurface()
                }
                // Columns are bounded by how many projects there are, not by the longest
                // chain — but a narrow window can still run out of room for them, and a
                // column you cannot scroll to is a column that is gone.
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 28) {
                        ForEach(chains) { chain in column(chain, inBatch: inBatch) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DotGrid())
    }

    // MARK: - The graph

    private var tasks: [NotebookCard] {
        NotebookIndex.visible(cards.filter { $0.kind == .task }, showDone: showDone)
    }

    /// Demos still waiting, newest file order, by the task they hold up.
    private var demos: [UserBlock] {
        blocks.filter { $0.isDemo && $0.waiting }
    }

    private func demo(for card: NotebookCard) -> UserBlock? {
        demos.first { $0.task == card.id }
    }

    /// One column per project, in dependency order, plus a last column for tasks filed
    /// under no project — those would otherwise be invisible on a board keyed by project.
    private var chains: [Chain] {
        let projects = NotebookIndex.ordered(cards.filter { $0.kind == .project })
        let all = cards.filter { $0.kind == .task }
        var built: [Chain] = projects.compactMap { project in
            let mine = all.filter { $0.project == project.id }
            guard !mine.isEmpty else { return nil }
            return chain(id: project.id, title: project.title, tasks: mine)
        }
        let known = Set(projects.map(\.id))
        let loose = all.filter { $0.project.map { !known.contains($0) } ?? true }
        if !loose.isEmpty {
            built.append(chain(id: "unfiled", title: "Not in a project", tasks: loose))
        }
        return built.filter { !$0.rows.isEmpty }
    }

    private func chain(id: String, title: String, tasks: [NotebookCard]) -> Chain {
        let done = tasks.filter { $0.status == "done" }.count
        let shown = NotebookIndex.ordered(NotebookIndex.visible(tasks, showDone: showDone))
        return Chain(
            id: id, title: title, done: done, total: tasks.count,
            rows: shown.map { Row(card: $0, lane: lane(of: $0), demo: demo(for: $0)) })
    }

    /// What a card gets to say about itself. Only the first four are worth a full card;
    /// the rest of a chain is one line until something is actually happening on it.
    private func lane(of card: NotebookCard) -> Lane {
        if card.status == "done" { return .done }
        if demo(for: card) != nil { return .demo }
        if card.status == "designing" { return .designing }
        // Blocked keeps its card wherever it sits in the chain: it is the one state that
        // is waiting on the user rather than on the work in front of it, so collapsing it
        // into the queue would hide the thing most worth acting on.
        if card.status == "blocked" { return .blocked }
        if assigned.contains(card.id) || card.status == "active" { return .active }
        return NotebookBoard.isReady(card, in: cards) ? .ready : .later
    }

    /// Ready means nothing it waits on is still outstanding. An id that resolves to
    /// nothing is not treated as a blocker — the amber unknown-id warning on the card is
    /// what says that, and a typo must not silently freeze the rest of the chain.
    static func isReady(_ card: NotebookCard, in cards: [NotebookCard]) -> Bool {
        card.dependsOn.allSatisfy { id in
            guard let blocker = cards.first(where: { $0.id == id }) else { return true }
            return blocker.kind == .project
                ? NotebookIndex.isFinished(blocker, in: cards)
                : blocker.status == "done"
        }
    }

    private var picked: [NotebookCard] {
        NotebookIndex.ordered(tasks.filter { selected.contains($0.id) })
    }

    /// What actually gets shipped: the picks plus the unfinished work they wait on, minus
    /// anything a still-open lead session already has.
    private var batch: [NotebookCard] {
        NotebookIndex.withBlockers(picked, in: cards, excluding: assigned)
    }

    // MARK: - Columns

    private func column(_ chain: Chain, inBatch: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chain.title).font(Typo.display(12.5)).foregroundStyle(Theme.tx)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(chain.done)/\(chain.total)")
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            }
            HStack(spacing: 8) {
                MeterBar(value: chain.total == 0 ? 0 : Double(chain.done) / Double(chain.total))
                Text(chain.id).font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(1)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)

            ForEach(Array(chain.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { connector }
                self.row(row, inBatch: inBatch)
            }
        }
        .frame(width: 300, alignment: .topLeading)
    }

    /// The chain drawn as a chain. It carries no information the order does not already —
    /// it is there so a column reads as one run of work rather than a stack of cards.
    private var connector: some View {
        Rectangle().fill(Theme.line2)
            .frame(width: 1, height: 12)
            .padding(.leading, 20)
    }

    // MARK: - Rows

    @ViewBuilder private func row(_ row: Row, inBatch: Set<String>) -> some View {
        let menu = CardMenu(card: row.card, busy: assigned.contains(row.card.id), remove: remove)
        switch row.lane {
        case .done:
            finished(row.card).contextMenu { menu }
        case .later:
            Button {
                selected = NotebookBoard.picking(row.card, from: selected)
            } label: {
                queued(row.card, inBatch: inBatch)
            }
            .buttonStyle(.plain)
            .contextMenu { menu }
        default:
            // Already out with a lead, or already shipped — not pickable into a batch that
            // would just hand it out again.
            if assigned.contains(row.card.id) {
                card(row, inBatch: inBatch).opacity(0.6).contextMenu { menu }
            } else {
                Button {
                    selected = NotebookBoard.picking(row.card, from: selected)
                } label: {
                    card(row, inBatch: inBatch)
                }
                .buttonStyle(.plain)
                .contextMenu { menu }
            }
        }
    }

    /// Finished work, only ever on screen with `Completed` on: one line, out of the way.
    private func finished(_ card: NotebookCard) -> some View {
        HStack(spacing: 9) {
            NotebookStyle.statusRing("done", progress: 1, size: 15)
            Text(card.title).font(Typo.text(12)).foregroundStyle(Theme.tx3).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Still behind something. One line — its title is all there is to decide with, and
    /// picking it pulls in whatever it waits on anyway.
    private func queued(_ card: NotebookCard, inBatch: Set<String>) -> some View {
        let isPicked = selected.contains(card.id)
        let inBatch = inBatch.contains(card.id)
        return HStack(spacing: 9) {
            Circle().strokeBorder(Theme.tx2.opacity(0.22), lineWidth: 2).frame(width: 15, height: 15)
            Text(card.title).font(Typo.text(12)).foregroundStyle(Theme.tx2).lineLimit(1)
            Spacer(minLength: 4)
            if card.isDesignWork { RoleTile(role: "design", size: 20) }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(inBatch ? Theme.card : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 9).strokeBorder(
                isPicked ? Theme.accent : (inBatch ? Theme.accent.opacity(0.35) : .clear),
                lineWidth: isPicked ? 1.5 : 1)
        )
        .opacity(selected.isEmpty || inBatch ? 1 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    /// The live edge of a chain, and the only place the board spends a whole card.
    private func card(_ row: Row, inBatch: Set<String>) -> some View {
        let card = row.card
        let isPicked = selected.contains(card.id)
        let inBatch = inBatch.contains(card.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                NotebookStyle.statusRing(
                    row.lane.status, progress: row.lane == .active ? 0.55 : 0,
                    size: 16
                )
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
                Button {
                    openCard(card)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tx3)
                }
                .buttonStyle(.borderless)
                .help("Open this task's page")
            }
            HStack(spacing: 6) {
                NotebookStyle.pill(row.lane.label, row.lane.tint)
                if assigned.contains(card.id) { NotebookStyle.pill("wip") }
                if !card.designer.isEmpty { NotebookStyle.chip(card.designer) }
                Spacer(minLength: 0)
                if card.isDesignWork { RoleTile(role: "design", size: 20) }
            }
            .padding(.top, 10)
            if let waits = NotebookStyle.edge("waits on ", unknown(card), in: cards) {
                waits.font(Typo.mono(10)).padding(.top, 9)
            }
            if let demo = row.demo {
                footer(demo)
            } else if row.lane == .designing {
                designing
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 11).strokeBorder(
                isPicked
                    ? Theme.accent
                    : (row.lane == .demo
                        ? Theme.amber.opacity(0.32)
                        : (inBatch ? Theme.accent.opacity(0.35) : Theme.line2)),
                lineWidth: isPicked ? 1.5 : 1)
        )
        .shadow(color: isPicked ? Theme.accent.opacity(0.25) : .clear, radius: 12, y: 4)
        .opacity(selected.isEmpty || inBatch ? 1 : 0.32)
        .contentShape(RoundedRectangle(cornerRadius: 11))
    }

    /// Order says what a card waits on now, so the line is kept only for the one thing
    /// order cannot show: an id that resolves to nothing, which is a typo in `depends_on`.
    private func unknown(_ card: NotebookCard) -> [String] {
        card.dependsOn.filter { id in !cards.contains { $0.id == id } }
    }

    private func footer(_ demo: UserBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.line2)
            HStack(alignment: .top, spacing: 10) {
                Text(
                    demo.action.isEmpty
                        ? "A demo is waiting. Nothing that depends on it starts until you have looked at it."
                        : demo.action
                )
                .font(Typo.text(11.5)).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            Button {
                openDemo(demo)
            } label: {
                Text("See demo")
            }
            .buttonStyle(.console)
        }
        .padding(.top, 12)
    }

    private var designing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.line2)
            Text("Being designed. Nothing is written to the repo yet.")
                .font(Typo.text(11.5)).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    /// Picking is a plain toggle: the board holds one kind of card now, and every one of
    /// them is a candidate for the same batch.
    static func picking(_ card: NotebookCard, from selected: Set<String>) -> Set<String> {
        selected.symmetricDifference([card.id])
    }

    // MARK: - Assign

    /// Design work in a batch changes what the button promises, because the lead hands
    /// those tasks to a designer, and the engineering tasks behind them wait on the user.
    private var designCount: Int { batch.filter(\.isDesignWork).count }

    private var assignBar: some View {
        ActionBar {
            if picked.isEmpty {
                Text("Pick the work. Full detail is on whatever could start next.")
                    .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
            } else {
                let pulled = batch.count - picked.count
                Text("\(picked.count) picked").font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                if pulled > 0 {
                    Text("· \(pulled) blocker\(pulled == 1 ? "" : "s") pulled in")
                        .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
                }
            }
            Spacer(minLength: 12)
            Button("Clear") { selected.removeAll() }
                .buttonStyle(.consoleGhost)
                .disabled(selected.isEmpty)
            // Never disabled and never about the picks: this one asks what should be on the
            // board at all, which is the question an empty or stalled board most needs.
            Button {
                review()
            } label: {
                Label("Product review", systemImage: "sparkles")
            }
            .buttonStyle(.console)
            Button {
                assign(batch)
            } label: {
                Label(
                    designCount > 0 ? "Assign — design first" : "Assign to Engineering Lead",
                    systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(.consolePrimary)
            .disabled(batch.isEmpty)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash").font(.system(size: 22))
                .foregroundStyle(Theme.tx4)
            Text(
                cards.contains { $0.kind == .task }
                    ? "Every task here is done."
                    : "No tasks yet — Product writes them."
            )
            .font(Typo.text(13)).foregroundStyle(Theme.tx3)
            Button {
                review()
            } label: {
                Label("Product review", systemImage: "sparkles")
            }
            .buttonStyle(.console)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGrid())
    }
}

extension NotebookBoard {
    /// One project's tasks in build order.
    struct Chain: Identifiable {
        let id: String
        let title: String
        let done: Int
        let total: Int
        let rows: [Row]
    }

    struct Row: Identifiable {
        let card: NotebookCard
        let lane: Lane
        /// The demo waiting on this task, when there is one.
        let demo: UserBlock?

        var id: String { card.id }
    }

    /// How much of a card is worth drawing, and what it says. The order is the order work
    /// moves through: design, your approval, an agent, the queue.
    enum Lane {
        case done, designing, demo, blocked, active, ready, later

        /// The notebook's own status word this lane draws as, so one palette covers both.
        var status: String {
            switch self {
            case .done: return "done"
            case .designing: return "designing"
            case .demo, .blocked: return "blocked"
            case .active: return "active"
            case .ready, .later: return "todo"
            }
        }

        var label: String {
            switch self {
            case .done: return "done"
            case .designing: return "designing"
            case .demo: return "demo ready"
            case .blocked: return "blocked"
            case .active: return "active"
            case .ready: return "ready"
            case .later: return "todo"
            }
        }

        var tint: Color { NotebookStyle.color(of: status) }
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
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(dot))
                    x += step
                }
                y += step
            }
        }
        .background(Theme.bg)
    }
}

/// The right-click menu on a notebook card, wherever one is shown. Delete is off while an
/// agent is on the work — pulling the file out from under a running lead only breaks it.
struct CardMenu: View {
    let card: NotebookCard
    let busy: Bool
    let remove: (NotebookCard) -> Void

    var body: some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([card.url]) }
        Divider()
        Button("Move to Trash", role: .destructive) { remove(card) }
            .disabled(busy)
    }
}
