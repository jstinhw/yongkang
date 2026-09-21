import Foundation
import Testing

@testable import YongkangCore

/// What a project's agents have going, in the order you should look at it: the running sessions
/// the sidebar and the Agents page list, and what else waits on you, which they only count.
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
        #expect(rows[1].title == "Task b", "a row's title is the task it is on")
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
        #expect(!rows.contains { $0.isRunningSession }, "none of these is a session the Agents tab lists")
    }

    @Test func aProposalWaitsOnTheSessionThatWroteIt() {
        let product = CodeSession(title: "Product", icon: "", line: "", agent: .claude)
        let project = Project(
            directory: directory, blocks: [block("idea", kind: "proposal", session: product.id)], sessions: [product])

        let rows = project.agentRows(summary: ChangeSummary())

        #expect(rows.count == 1, "the proposal is the session's, not a row of its own")
        #expect(rows.first?.isRunningSession == true && rows.first?.state == .needsYou)
        #expect(rows.first?.reason == "wants your opinion")
    }

    @Test func aQuestionOnScreenLeavesItsBlockARowOfItsOwn() {
        let product = CodeSession(title: "Product", icon: "", line: "", agent: .claude)
        let project = Project(
            directory: directory, blocks: [block("idea", kind: "proposal", session: product.id)], sessions: [product])

        let rows = project.agentRows(summary: ChangeSummary(), asking: [product.id: "Allow Bash?"])

        #expect(rows.map(\.id) == [product.id.uuidString, "block:idea"], "both need you")
        #expect(rows[0].reason == "Allow Bash?" && rows[0].block == nil, "the session's row is the question")
    }

    @Test func onlyARunningSessionsOwnRowIsListedUnderAgents() {
        let session = CodeSession(
            title: "Claude Code", icon: "", line: "", agent: .claude, taskIDs: ["built", "deploy"])
        let project = Project(directory: directory, blocks: [block("token", task: "deploy")], sessions: [session])
        let summary = ChangeSummary(tasks: [
            done("built"), SummaryTask(id: "deploy", title: "Deploy", status: "blocked"),
        ])

        let rows = project.agentRows(summary: summary)

        #expect(rows.count == 2, "its block and the work it finished are both counted")
        #expect(rows.filter(\.isRunningSession).map(\.id) == [session.id.uuidString], "but it is one agent")
    }

    @Test func theBoardListsEveryTaskThatIsNotIdle() {
        func task(_ id: String, _ status: String = "todo") -> NotebookCard {
            NotebookCard(
                id: id, url: directory, kind: .task, title: "Task \(id)", status: status, project: nil, dependsOn: [])
        }
        let session = CodeSession(title: "Codex", icon: "", line: "", agent: .codex, taskIDs: ["running", "demo"])
        let project = Project(
            directory: directory,
            cards: [
                task("idle"), task("running", "active"), task("reviewed", "done"), task("demo"), task("old", "done"),
            ],
            blocks: [block("look", kind: "demo", task: "demo")], sessions: [session])
        let summary = ChangeSummary(tasks: [done("reviewed")])

        let rows = project.taskRows(summary: summary)

        #expect(rows.map(\.id) == ["task:demo", "task:reviewed", "task:running"], "nothing idle, and needs you first")
        #expect(rows[0].route == .block("look") && rows[0].session?.id == session.id, "who it is waiting with")
        #expect(rows[1].route == .reviewTask("reviewed"))
        #expect(rows[2].route == .task("running") && rows[2].title == "Task running")
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
