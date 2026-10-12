import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The number beside a project in the sidebar counts what it lists under it in that section.
@Suite struct SidebarCountTests {
    /// `first-release` held two open blocks, and the sidebar showed 2 beside one task under Board.
    @Test func aTaskHeldUpByTwoBlocksCountsOnceUnderBoard() {
        let directory = URL(fileURLWithPath: "/tmp/app")
        func block(_ id: String) -> UserBlock {
            UserBlock(
                id: id, url: directory.appendingPathComponent("\(id).md"), slug: id, title: "Block \(id)",
                status: "open", kind: "block", stage: "", session: nil, action: "", link: nil, task: "release",
                resolution: "", body: "", before: nil, branch: "", revisions: [])
        }
        let task = NotebookCard(
            id: "release", url: directory, kind: .task, title: "Release", status: "active", project: nil,
            dependsOn: [])
        let project = Project(directory: directory, cards: [task], blocks: [block("tag"), block("secrets")])

        let item = SidebarProject(project: project, summary: ChangeSummary())

        #expect(item.tasks.count == 1)
        #expect(item.needsYou(in: .board) == 1, "one task listed, one counted")
        #expect(item.needsYou(in: .agents) == 0, "no running session, nothing listed under Agents")
        #expect(item.toReview(in: .board) == 0 && item.toReview(in: .agents) == 0)
    }
}
