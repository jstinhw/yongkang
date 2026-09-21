import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The board's outline: which card a task is drawn under, when a column steps in, and what
/// the indent cannot say and so has to spell out.
@Suite struct BoardOutlineTests {

    private func task(
        _ id: String, _ status: String = "todo", waits: [String] = [], kind: EntryKind = .task
    ) -> NotebookCard {
        NotebookCard(
            id: id, url: URL(fileURLWithPath: "/tmp/\(id).md"), kind: kind, title: id,
            status: status, project: "p", dependsOn: waits)
    }

    private func place(_ cards: [NotebookCard]) -> [BoardOutline.Placement] {
        BoardOutline.place(NotebookIndex.ordered(cards), in: cards)
    }

    /// The whole reason the tick was wrong: cards the sort happens to stack are not a chain.
    @Test func independentTasksAreJoinedToNothing() {
        let placed = place([task("a"), task("b"), task("c")])

        #expect(placed.map(\.id) == ["a", "b", "c"])
        #expect(placed.allSatisfy { !$0.tick && !$0.fork && $0.depth == 0 })
    }

    /// A run is the case an indent would only make worse: twenty links, still one column.
    @Test func aRunStaysAtOneIndent() {
        let ids = (0..<20).map { "t\($0)" }
        let chain = ids.enumerated().map { index, id in
            task(id, waits: index == 0 ? [] : [ids[index - 1]])
        }

        let placed = place(chain)
        #expect(placed.map(\.id) == ids, "build order, unchanged")
        #expect(placed.allSatisfy { $0.depth == 0 }, "nesting every link would walk off the column")
        #expect(placed.dropFirst().allSatisfy { $0.tick }, "each is joined to the one above")
        #expect(placed[0].tick == false, "except the root, which waits on nothing")
    }

    /// One step, only where something actually splits — and the long branch last, so it is
    /// the child drawn directly under its parent.
    @Test func aForkStepsInAndKeepsItsLongBranchLast() {
        let placed = place([
            task("root"),
            task("short", waits: ["root"]),
            task("long", waits: ["root"]),
            task("longer", waits: ["long"]),
        ])

        #expect(placed.map(\.id) == ["root", "short", "long", "longer"])
        #expect(placed[1].fork && placed[1].depth == 1, "a fork's child steps in once")
        #expect(placed[2].fork && placed[2].depth == 1)
        #expect(placed[3].depth == 1, "and its branch runs on flat from there")
        #expect(placed[3].tick, "joined to the card above, not stepped in again")
    }

    /// Position can only put a card under one thing. The second blocker is said in words.
    @Test func aSecondParentIsNamedRatherThanDrawn() throws {
        let placed = place([
            task("one"), task("two"),
            task("merge", waits: ["one", "two"]),
        ])

        let merge = try #require(placed.first { $0.id == "merge" })
        #expect(merge.tick, "drawn under the last of its blockers")
        #expect(merge.also == ["one"], "the other one it names")
        #expect(merge.joined, "so the card says 'also waits on'")
    }

    /// A blocker that is finished is not in anyone's way, and a card that says so about
    /// every one of them is just noise.
    @Test func finishedBlockersAreNotNamed() {
        let placed = place([task("built", "done"), task("next", waits: ["built"])])

        #expect(placed.last?.also.isEmpty == true)
    }

    /// The one thing the old board did spell out, and the reason `cleared` will not treat an
    /// id it cannot find as satisfied.
    @Test func anUnknownIdIsAlwaysNamed() {
        let cards = [task("only", waits: ["typo"])]
        let placed = place(cards)

        #expect(placed[0].also == ["typo"])
        #expect(placed[0].joined == false, "nothing is drawn above it, so it reads 'waits on'")
        #expect(
            NotebookBoard.isReady(cards[0], in: cards),
            "a typo still must not freeze the rest of the column")
    }

    /// A task filed under another project, or hidden by `Completed`, is not in this column to
    /// be drawn under — it comes back as a word.
    @Test func aBlockerOutsideTheColumnIsNamed() {
        let elsewhere = task("theirs", project: nil)
        let mine = task("mine", waits: ["theirs"])

        let placed = BoardOutline.place([mine], in: [elsewhere, mine])
        #expect(placed[0].also == ["theirs"])
        #expect(placed[0].depth == 0)
    }

    /// Past the ceiling the column stops stepping in and starts talking.
    @Test func theIndentStopsAtItsCeiling() throws {
        var cards: [NotebookCard] = [task("r")]
        var parent = "r"
        // Each level is a fork, so each would step in if nothing stopped it.
        for level in 0..<6 {
            cards.append(task("leaf\(level)", waits: [parent]))
            cards.append(task("down\(level)", waits: [parent]))
            parent = "down\(level)"
        }

        let placed = place(cards)
        #expect(placed.allSatisfy { $0.depth <= BoardOutline.maxDepth })
        let capped = try #require(placed.first { $0.depth == BoardOutline.maxDepth && $0.also.contains("down2") })
        #expect(capped.fork == false, "out of room to step in")
        #expect(capped.joined == false, "so nothing drawn says what it waits on")
    }

    /// Whatever the graph does, every visible task is drawn exactly once. A cycle in
    /// `depends_on` is a broken notebook, not a reason to lose a card off the board.
    @Test func everyTaskIsPlacedOnceEvenInACycle() {
        let cards = [
            task("a", waits: ["c"]), task("b", waits: ["a"]), task("c", waits: ["b"]),
            task("loose"),
        ]

        let placed = place(cards)
        #expect(placed.map(\.id).sorted() == ["a", "b", "c", "loose"])
        #expect(Set(placed.map(\.id)).count == placed.count)
    }
}

extension BoardOutlineTests {
    fileprivate func task(_ id: String, project: String?) -> NotebookCard {
        NotebookCard(
            id: id, url: URL(fileURLWithPath: "/tmp/\(id).md"), kind: .task, title: id,
            status: "todo", project: project, dependsOn: [])
    }
}
