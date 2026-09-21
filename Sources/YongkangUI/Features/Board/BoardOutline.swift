import SwiftUI
import YongkangCore

/// Where each of a project's tasks sits in its column: the order they are drawn in, how far
/// each is stepped in, and what joins it to what.
///
/// Nesting every `depends_on` link is what makes an outline expensive. A straight chain of
/// twenty tasks would walk twenty steps off the right edge of a 300pt column, and not one of
/// those steps would say anything a line between two cards does not. So a step in marks a
/// *fork*, never a link: one task waiting on a card continues the run at the same indent, and
/// only a card with two or more waiting on it steps its children in. Indent counts the forks
/// on the path rather than the tasks, which is one or two in practice, so how deep a project
/// runs stops deciding how wide its column has to be.
///
/// What the outline cannot draw, it says: a second parent, a blocker in another project, one
/// hidden by `Completed`, and an id that resolves to nothing all come back in `also`.
///
/// Pure, and tested off the main actor — it is a rule about cards, not about a view, the same
/// way `NotebookBoard.isReady` is.
enum BoardOutline {
    /// Three steps, 48pt of a 300pt column, is the ceiling. A fourth fork stops stepping in
    /// and names its blocker in words instead — the line a second parent already gets.
    // ponytail: if real notebooks start running four forks deep, widen the column before
    // raising this. The words stay readable; a 64pt indent does not leave a title room.
    static let maxDepth = 3

    /// One step in. The cards sit 20pt short of their status ring, so a step of 16 puts a
    /// child's ring exactly one step right of its parent's and the elbow between them is
    /// ring to ring.
    static let step: CGFloat = 16

    struct Placement: Equatable {
        let id: String
        /// Steps in, `0...maxDepth`.
        let depth: Int
        /// It waits on the card drawn directly above it, at the same indent.
        let tick: Bool
        /// It hangs off the card above and to the left, which has more than one thing
        /// waiting on it.
        let fork: Bool
        /// The blockers position cannot show.
        let also: [String]

        /// Whether something drawn already says what this waits on, which is the whole
        /// difference between "waits on" and "also waits on".
        var joined: Bool { tick || fork }
    }

    /// `shown` is one project's visible tasks in build order. `cards` is the whole notebook,
    /// because a blocker that is finished, filed under another project or misspelled is not
    /// in `shown` and still has to be accounted for.
    static func place(_ shown: [NotebookCard], in cards: [NotebookCard]) -> [Placement] {
        let rank = Dictionary(shown.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The blocker a card is drawn under is the *last* of the ones above it, so the card
        // continues the longest run rather than hanging off the earliest thing it needs. A
        // blocker that is not above it is no parent: that is a cycle in `depends_on`, and an
        // outline built from one would not terminate.
        var parents: [String: String] = [:]
        var also: [String: [String]] = [:]
        for card in shown {
            let mine = rank[card.id] ?? 0
            let parent = card.dependsOn
                .filter { (rank[$0] ?? Int.max) < mine }
                .max { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
            parents[card.id] = parent
            also[card.id] = card.dependsOn.filter { $0 != parent && !cleared($0, in: cards) }
        }

        var children: [String: [String]] = [:]
        for card in shown {
            guard let parent = parents[card.id] else { continue }
            children[parent, default: []].append(card.id)
        }

        // How much work hangs off each card. A parent is always above its children, so one
        // pass upwards has every child's total by the time it needs it.
        var sizes: [String: Int] = [:]
        for card in shown.reversed() {
            sizes[card.id] = 1 + (children[card.id] ?? []).reduce(0) { $0 + (sizes[$1] ?? 1) }
        }

        // Shortest first, wherever a column has a choice. Under a fork it keeps the branch
        // that runs on longest directly under the card it hangs off; at the top of a column
        // it keeps the work that could start now above the chain that cannot, instead of
        // burying three ready tasks under someone else's six-card run.
        func shortestFirst(_ ids: [String]) -> [String] {
            ids.enumerated()
                .sorted { first, second in
                    let (one, two) = (sizes[first.element] ?? 1, sizes[second.element] ?? 1)
                    return one == two ? first.offset < second.offset : one < two
                }
                .map(\.element)
        }

        var placed: [Placement] = []
        func walk(_ id: String, depth: Int, tick: Bool, fork: Bool) {
            placed.append(
                Placement(id: id, depth: depth, tick: tick, fork: fork, also: also[id] ?? []))
            let kids = shortestFirst(children[id] ?? [])
            guard kids.count > 1 else {
                if let only = kids.first { walk(only, depth: depth, tick: true, fork: false) }
                return
            }
            for kid in kids {
                guard depth < maxDepth else {
                    // Out of room to step in. What the indent would have said goes into the
                    // card's own line instead, ahead of whatever else it names.
                    also[kid, default: []].insert(id, at: 0)
                    walk(kid, depth: depth, tick: false, fork: false)
                    continue
                }
                walk(kid, depth: depth + 1, tick: false, fork: true)
            }
        }
        for root in shortestFirst(shown.filter { parents[$0.id] == nil }.map(\.id)) {
            walk(root, depth: 0, tick: false, fork: false)
        }
        return placed
    }

    /// A blocker that is no longer in anyone's way: a done task, or a project whose work is
    /// all done. An id that resolves to nothing is *not* cleared — a typo in `depends_on` is
    /// only ever visible because a card says it, which is what the amber id in the line is for.
    static func cleared(_ id: String, in cards: [NotebookCard]) -> Bool {
        guard let blocker = cards.first(where: { $0.id == id }) else { return false }
        return blocker.kind == .project
            ? NotebookIndex.isFinished(blocker, in: cards)
            : blocker.status == "done"
    }

    /// The line a fork's child hangs from: down the column of its parent's status ring, then
    /// right into its own. It crosses the card's leading padding on purpose — ring to ring is
    /// what reads as "this one waits on that one".
    struct Elbow: Shape {
        let depth: Int
        /// How far down the row its own status ring sits.
        let node: CGFloat

        func path(in rect: CGRect) -> Path {
            let from = CGFloat(depth - 1) * step + 20
            let into = CGFloat(depth) * step + 12
            var path = Path()
            path.move(to: CGPoint(x: from, y: 0))
            path.addLine(to: CGPoint(x: from, y: node - 6))
            path.addQuadCurve(
                to: CGPoint(x: from + 6, y: node), control: CGPoint(x: from, y: node))
            path.addLine(to: CGPoint(x: into, y: node))
            return path
        }
    }
}
