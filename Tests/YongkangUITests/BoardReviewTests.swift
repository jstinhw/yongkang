import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// What the board keeps on screen after an agent has ticked a task off. A finished task is
/// only finished once its work is committed, and the two screens have to agree on that: the
/// Agents list called three tasks "ready for review" while the board showed none of them.
@Suite struct BoardReviewTests {
    private func task(_ id: String, _ status: String) -> NotebookCard {
        NotebookCard(
            id: id, url: URL(fileURLWithPath: "/tmp/\(id).md"), kind: .task, title: id,
            status: status, project: "p", dependsOn: [])
    }

    @Test func doneWorkNobodyCommittedStaysOnTheBoard() {
        let cards = [task("built", "done"), task("landed", "done"), task("next", "todo")]
        let shown = NotebookBoard.visible(cards, showDone: false, reviewing: ["built"])
        #expect(
            shown.map(\.id) == ["built", "next"],
            "the task waiting for review stays; the one already committed goes")
        #expect(
            NotebookBoard.visible(cards, showDone: true, reviewing: []).count == 3,
            "Completed on still shows everything")
    }

    /// The set the board is handed is the same one the Agents list counts, so neither screen
    /// can decide on its own what is waiting.
    @Test func reviewingIsWhatTheAgentsListCounts() {
        let summary = ChangeSummary(tasks: [
            SummaryTask(
                id: "built", title: "Built", status: "done",
                files: [FileChange(path: "app/page.tsx", added: 40, removed: 0, untracked: true)]),
            SummaryTask(id: "landed", title: "Landed", status: "done"),
            SummaryTask(id: "next", title: "Next", status: "todo"),
        ])
        #expect(summary.waitingIDs == ["built"], "done plus uncommitted files, and nothing else")
    }
}
