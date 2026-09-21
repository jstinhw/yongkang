import Foundation
import Testing

@testable import YongkangCore

/// The rows the sidebar lists under a project and its Agents page draws: one per agent worth
/// looking at, in the order you should look at them.
@Suite struct AgentRowTests {
    private let directory = URL(fileURLWithPath: "/tmp/app")

    private func block(_ id: String, kind: String = "gate", session: UUID? = nil, task: String? = nil) -> UserBlock {
        UserBlock(
            id: id, url: directory.appendingPathComponent("\(id).md"), slug: id, title: "Block \(id)",
            status: "open", kind: kind, stage: "", session: session, action: "", link: nil, task: task,
            resolution: "", body: "", before: nil, branch: "", revisions: [])
    }

    private func done(_ id: String) -> SummaryTask {
        SummaryTask(
            id: id, title: "Task \(id)", status: "done",
            files: [FileChange(path: "\(id).swift", added: 1, removed: 0, untracked: false)])
    }

    @Test func aQuestionOutranksReviewAndReviewOutranksWork() {
        let working = CodeSession(title: "Claude Code", icon: "", line: "", agent: .claude, taskIDs: ["a"])
        let finished = CodeSession(title: "Codex", icon: "", line: "", agent: .codex, taskIDs: ["b"])
        let asking = CodeSession(title: "Grok", icon: "", line: "", agent: .grok, taskIDs: ["c"])
        let project = Project(directory: directory, sessions: [working, finished, asking])
        let summary = ChangeSummary(tasks: [SummaryTask(id: "a", title: "Task a", status: "active"), done("b")])

        let rows = project.agentRows(summary: summary, asking: [asking.id: "Run swift test?"])

        #expect(rows.map(\.state) == [.needsYou, .review, .working])
        #expect(rows[0].reason == "Run swift test?", "the question is what the row says")
        #expect(rows[1].title == "Task b", "a row is named after its task, not its CLI")
        #expect(rows.allSatisfy { $0.route == .session($0.session!.id) }, "a live agent opens on itself")
    }

    @Test func aBlockOnASessionsTaskIsThatSessionWaitingOnYou() {
        let session = CodeSession(title: "Claude Code", icon: "", line: "", agent: .claude, taskIDs: ["deploy"])
        let project = Project(directory: directory, blocks: [block("token", task: "deploy")], sessions: [session])

        let rows = project.agentRows(summary: ChangeSummary())

        #expect(rows.count == 1, "the block is the session's, not a row of its own")
        #expect(rows.first?.state == .needsYou)
        #expect(rows.first?.reason == "Block token")
    }

    @Test func whatNoSessionHoldsStillGetsARow() {
        let gone = CodeSession(
            title: "Claude Code", icon: "", line: "", agent: .claude, taskIDs: ["old"], exited: true)
        let idle = CodeSession(
            title: "Codex", icon: "", line: "", agent: .codex, taskIDs: ["finished"], exited: true)
        let project = Project(
            directory: directory, blocks: [block("idea", kind: "proposal")], sessions: [gone, idle])
        let summary = ChangeSummary(tasks: [done("old"), done("orphan")])

        let rows = project.agentRows(summary: summary)

        #expect(rows.map(\.id) == ["block:idea", gone.id.uuidString, "task:orphan"])
        #expect(rows[0].reason == "wants your opinion")
        #expect(rows[1].route == .reviewTask("old"), "a dead session opens on the work it left")
        #expect(!rows.contains { $0.session?.id == idle.id }, "an exited session with nothing waiting is history")
    }

    @Test func finishedWorkIsNotHiddenBehindABlock() {
        let session = CodeSession(
            title: "Claude Code", icon: "", line: "", agent: .claude, taskIDs: ["built", "deploy"])
        let project = Project(directory: directory, blocks: [block("token", task: "deploy")], sessions: [session])
        let summary = ChangeSummary(tasks: [
            done("built"), SummaryTask(id: "deploy", title: "Deploy", status: "blocked"),
        ])

        let rows = project.agentRows(summary: summary)

        #expect(rows.map(\.state) == [.needsYou, .review])
        #expect(rows[0].title == "Deploy", "the blocked row is about the task the block holds up")
        #expect(rows[1].route == .reviewTask("built") && rows[1].session?.id == session.id)
    }
}
