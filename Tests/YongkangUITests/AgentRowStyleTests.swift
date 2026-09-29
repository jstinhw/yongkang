import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// How a row reads in the two columns that draw one: the sidebar under its project, and the
/// cards on a project's Agents page. Both lead with the work and note the CLI under it —
/// "Run 2 ready" starts two sessions at once, and two rows called "Claude Code" and
/// "Claude Code 2" say nothing about which is which.
@Suite @MainActor struct AgentRowStyleTests {
    private func row(task: String?, title: String, session: CodeSession?) -> AgentRow {
        AgentRow(
            id: session?.id.uuidString ?? "x", state: .working, title: title, reason: nil,
            session: session, task: task, block: nil,
            route: session.map { .session($0.id) } ?? .agents)
    }

    @Test func aSessionOnATaskIsNamedAfterTheTask() {
        let session = CodeSession(title: "Claude Code 2", icon: "c", line: "claude", agent: .claude)
        let row = row(task: "ship-it", title: "Put the landing page on Vercel", session: session)

        #expect(row.label == "Put the landing page on Vercel", "the work, not the CLI running it")
        #expect(row.agentName == "Claude Code", "and the CLI without the number that told two apart")
        #expect(row.line == "working · Claude Code")
    }

    @Test func aSessionOnNoTaskIsNamedAfterItself() {
        let session = CodeSession(title: "Product", icon: "s", line: "claude", agent: .claude)
        let row = row(task: nil, title: "Product", session: session)

        #expect(row.label == "Product", "there is no work to name it after")
        #expect(row.line == "working", "and nothing to add: the row already says who it is")
    }

    @Test func aServiceRunnerKeepsItsOwnName() {
        let session = CodeSession(title: "web", icon: "t", line: "npm run dev")
        let row = row(task: nil, title: "web", session: session)

        #expect(row.label == "web" && row.agentName == "web")
        #expect(row.doing == "running", "not 'working': nobody is agentic about `npm run dev`")
    }
}
