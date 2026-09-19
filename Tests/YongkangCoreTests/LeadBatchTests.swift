import Foundation
import Testing

@testable import YongkangCore

@Suite struct LeadBatchTests {
    private let anyURL = URL(fileURLWithPath: "/tmp")

    // Neither CLI records which task a subagent is for, so the link is its own name —
    // however that provider slugs it, and longest id first so a prefix cannot steal it.
    @Test(
        arguments: [
            ("edit_todo_frontend_dev", "edit-todo", "a Codex-slugged name links to its task"),
            ("qa-dev: deploy-to-vercel", "deploy-to-vercel", "a Claude description links to its task"),
            ("Edit Todo API (backend)", "edit-todo-api", "the longer id wins over the one that is its prefix"),
            ("Compact conversation", nil, "a subagent named after no task belongs to no task"),
        ] as [(String, String?, String)])
    func subagentLinksToTheTaskItsNameCarries(label: String, taskID: String?, why: String) {
        let batch = ["edit-todo", "edit-todo-api", "deploy-to-vercel"]
        #expect(Subagents.taskID(in: label, from: batch) == taskID, "\(why)")
    }

    @Test func subagentsGroupUnderEveryAssignedTask() {
        let grouped = Subagents.grouped(
            [
                SubagentStatus(
                    id: "frontend", description: "build-ui-foundation-frontend-dev",
                    agentType: "frontend-dev", running: false, transcriptURL: anyURL,
                    taskID: "build-ui-foundation"),
                SubagentStatus(
                    id: "qa", description: "build-ui-foundation-qa-dev",
                    agentType: "qa-dev", running: true, transcriptURL: anyURL,
                    taskID: "build-ui-foundation"),
            ], by: ["build-ui-foundation", "waiting-on-dependency"])
        #expect(
            grouped.map(\.id) == ["build-ui-foundation", "waiting-on-dependency"]
                && grouped.map(\.subagents.count) == [2, 0],
            "a lead's subagents are grouped under every assigned task")
        #expect(
            Subagents.runningTaskIDs(grouped.flatMap(\.subagents)) == ["build-ui-foundation"],
            "a running child keeps its task in WIP")
        #expect(
            CodeSession(
                title: "Engineering Lead", icon: "person.2", line: "claude",
                subagents: grouped.flatMap(\.subagents)
            )
            .activeSubagents.map(\.id) == ["qa"],
            "a finished agent drops off the lead's lists")
    }

    // Who a task's page and the Overview show as working on it. One session per chain means
    // the session itself is usually the worker, and only listing subagents showed nobody.
    @Test func aTaskListsItsSessionAndTheSubagentsUnderIt() {
        let child = SubagentStatus(
            id: "child", description: "wire-auth", agentType: "general-purpose", running: true,
            transcriptURL: anyURL, taskID: "wire-auth")
        let live = CodeSession(
            title: "Wire auth", icon: "", line: "", agent: .claude,
            taskIDs: ["wire-auth"], subagents: [child])
        let gone = CodeSession(
            title: "Ship it", icon: "", line: "", agent: .claude, taskIDs: ["ship-it"], exited: true)
        var project = Project(directory: anyURL, entries: [])
        project.sessions = [live, gone]

        let working = project.agents(on: "wire-auth")
        #expect(
            working.map(\.title) == ["Wire auth", "general-purpose"],
            "the session holding the task comes first, then what it dispatched for it")
        #expect(working.first?.route == .session(live.id), "clicking the session opens that session")
        #expect(
            working.last?.route == .subagent(session: live.id, id: "child"),
            "clicking a subagent opens its live child view")
        #expect(project.agents(on: "ship-it").isEmpty, "an exited session is nobody working")
        #expect(
            project.runningAgents.map(\.title) == ["Wire auth", "general-purpose"],
            "everything running is the live sessions on work and the subagents under them")
    }

    // A blocker is pulled into the batch rather than raised as a question.
    private let graph = [
        node("a", "todo", ["b"]), node("b", "todo", ["c"]), node("c", "todo", []),
        node("d", "todo", ["done-one"]), node("done-one", "done", ["c"]),
        node("x", "todo", ["y"]), node("y", "todo", ["x"]),
    ]

    // What can be worked on side by side: one session per chain, so two tasks that wait on
    // nothing never sit behind each other in one agent's queue.
    @Test func aBatchSplitsIntoChainsThatCanRunApart() {
        let batch = [node("a", "todo", ["b"]), node("b", "todo", []), node("solo", "todo", [])]
        #expect(
            NotebookIndex.chains(batch).map { $0.map(\.id) } == [["b", "a"], ["solo"]],
            "a task and its blocker are one chain, in build order; work waiting on nothing is its own")
        #expect(
            NotebookIndex.chains(graph).map { $0.map(\.id).sorted() } == [
                ["a", "b", "c", "d", "done-one"], ["x", "y"],
            ],
            "tasks joined through another task are one chain, and a cycle does not split")
        #expect(NotebookIndex.chains([]).isEmpty)
    }

    @Test func blockersArePulledIntoTheBatch() {
        #expect(
            NotebookIndex.withBlockers([graph[0]], in: graph).map(\.id) == ["c", "b", "a"],
            "blockers come along transitively, and ahead of what they block")
        #expect(
            NotebookIndex.withBlockers([graph[3]], in: graph).map(\.id) == ["d"],
            "a finished blocker is not dragged back in, nor anything behind it")
        #expect(
            Set(NotebookIndex.withBlockers([graph[5]], in: graph).map(\.id)) == ["x", "y"],
            "a dependency cycle terminates instead of hanging")
    }

    // A task can wait on a whole project. Pull in that project's unfinished tasks,
    // not the project card: only task files can be assigned to Engineering Lead.
    @Test func projectBlockerContributesItsUnfinishedTasks() {
        let projectBlocker = NotebookCard(
            id: "edit-and-order", url: URL(fileURLWithPath: "/project.md"),
            kind: .project, title: "Edit and order", status: "todo",
            project: nil, dependsOn: ["todo-crud"])
        let finishedProject = NotebookCard(
            id: "todo-crud", url: URL(fileURLWithPath: "/crud.md"),
            kind: .project, title: "CRUD", status: "done",
            project: nil, dependsOn: [])
        let projectGraph = [
            node("builder-ui-foundation", "todo", ["edit-and-order"], project: "builder-ui-redesign"),
            projectBlocker,
            node("edit-todo", "active", ["toggle-and-delete"], project: "edit-and-order"),
            node("sort-order", "done", ["toggle-and-delete"], project: "edit-and-order"),
            finishedProject,
            node("toggle-and-delete", "done", [], project: "todo-crud"),
        ]
        let projectBatch = NotebookIndex.withBlockers([projectGraph[0]], in: projectGraph)
        #expect(
            projectBatch.map(\.id) == ["edit-todo", "builder-ui-foundation"],
            "an unfinished project blocker contributes all of its unfinished tasks")
        #expect(
            projectBatch.last?.dependsOn == ["edit-todo"],
            "the lead sees the concrete task prerequisite, not an unassignable project page")
    }

    @Test func emptyPickAndDoneVisibility() {
        #expect(NotebookIndex.withBlockers([], in: graph).isEmpty)
        #expect(NotebookIndex.visible([graph[0], graph[4]], showDone: false).map(\.id) == ["a"])
        #expect(NotebookIndex.visible([graph[0], graph[4]], showDone: true).map(\.id) == ["a", "done-one"])
    }

    // A project is off the board once its last task passes, without anything having
    // written `status: done` on the project file itself.
    @Test func projectFinishesWhenItsLastTaskPasses() {
        let shipped = NotebookCard(
            id: "shipped", url: anyURL, kind: .project, title: "Shipped",
            status: "active", project: nil, dependsOn: [])
        let openProject = NotebookCard(
            id: "wip", url: anyURL, kind: .project, title: "WIP",
            status: "active", project: nil, dependsOn: [])
        let projectTasks = [
            NotebookCard(
                id: "t1", url: anyURL, kind: .task, title: "One", status: "done",
                project: "shipped", dependsOn: []),
            NotebookCard(
                id: "t2", url: anyURL, kind: .task, title: "Two", status: "todo",
                project: "wip", dependsOn: []),
        ]
        let rail = [shipped, openProject] + projectTasks
        #expect(NotebookIndex.isFinished(shipped, in: rail), "every task done finishes the project")
        #expect(!NotebookIndex.isFinished(openProject, in: rail), "one task left keeps it on the board")
        #expect(
            !NotebookIndex.isFinished(shipped, in: [shipped]),
            "a project with no tasks yet is not finished")
    }

    // A task already claimed by another lead is not handed to a second one, whether it
    // was picked directly or would otherwise be pulled in as a blocker.
    @Test func claimedTasksAreNotHandedToASecondLead() {
        #expect(
            NotebookIndex.withBlockers([graph[0]], in: graph, excluding: ["a"]).isEmpty,
            "an already-assigned pick is dropped, not reassigned")
        #expect(
            NotebookIndex.withBlockers([graph[0]], in: graph, excluding: ["b"]).map(\.id) == ["a"],
            "an already-assigned blocker is not pulled in twice")
        #expect(
            NotebookIndex.withBlockers([graph[4]], in: graph).isEmpty,
            "a task already done cannot be picked again, nor does it drag in its own blockers")
    }

    @Test func wipIsTheUnionOfOpenSessionsTasks() {
        var wip = Project(directory: anyURL)
        wip.sessions = [
            CodeSession(title: "Engineering Lead", icon: "person.2", line: "", taskIDs: ["a", "b"]),
            CodeSession(title: "Engineering Lead 2", icon: "person.2", line: "", taskIDs: ["c"]),
        ]
        #expect(
            wip.assignedTaskIDs == ["a", "b", "c"],
            "a project's WIP set is the union of its open sessions' tasks")
        wip.sessions[0].exited = true
        #expect(
            wip.assignedTaskIDs == ["c"],
            "an exited lead no longer blocks dependency dispatch")
    }

    // Lanes are levels: everything in one can start once the lanes left of it are done.
    @Test func lanesAreLevels() {
        #expect(
            NotebookIndex.waves(graph).map { $0.map(\.id) }
                == [["c"], ["b", "done-one"], ["a", "d"], ["x", "y"]],
            "a chain steps one lane at a time, and a cycle lands in the last lane")
        #expect(NotebookIndex.waves([]).isEmpty)
    }
}

private func node(_ id: String, _ status: String, _ waits: [String], project: String? = nil) -> NotebookCard {
    NotebookCard(
        id: id, url: URL(fileURLWithPath: "/\(id).md"), kind: .task,
        title: id, status: status, project: project, dependsOn: waits)
}
