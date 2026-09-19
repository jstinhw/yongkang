import Foundation
import Testing

@testable import YongkangCore

@Suite struct LeadPromptTests {
    /// The task pages a batch is picked from: two made the way the app makes them (the same
    /// title, so the second is `wire-auth-2`) and one written by hand, colon in the title.
    private func pickedTasks(in project: URL) throws -> [NotebookCard] {
        let root = NotebookFormat.root(in: project)
        _ = try NotebookFormat.create(.project, title: "Launch Beta", in: root, project: nil, roadmap: "ship-beta")
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch-beta")
        try fixture("notebook/c-tricky-task.md")
            .write(to: root.appendingPathComponent("tasks/tricky.md"), atomically: true, encoding: .utf8)
        return NotebookIndex.load(root: root).filter { $0.kind == .task }
    }

    /// What zsh actually passes to the agent for a given quoted argument.
    private func echo(_ quotedArgument: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf %s \(quotedArgument)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Picked tasks reach the agent as links, without duplicating their page descriptions,
    // with what the app reads back: its session id, a report per task, and no commits.
    @Test func pickedTasksReachTheAgentAsLinks() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let picked = try pickedTasks(in: tmp)
        try #require(picked.count >= 2)
        let sessionID = UUID()
        let id = sessionID.uuidString.lowercased()
        let brief = NotebookFormat.workPrompt(tasks: picked, sessionID: sessionID)

        #expect(brief.contains("Session id: \(id)"), "a block or demo has to name the session waiting on it")
        for task in picked {
            #expect(brief.contains(task.id) && !brief.contains(task.title))
            #expect(
                brief.contains(".notebook/tasks/\(task.url.deletingPathExtension().lastPathComponent).md"),
                "the agent needs a path it can open from the project root")
        }
        #expect(
            brief.contains(".notebook/runs/\(id)-work-<work id>.md") && brief.contains("## Verification"),
            "each task's report is filed where Review reads it, with how it was checked")
        #expect(brief.contains("Never stage, commit"), "the user commits each task from Review")
        #expect(!brief.contains("designer"), "no design task, no designer")
        let echoed = try echo(AgentCommand.quoted(brief))
        #expect(echoed == brief, "task brief mangled by the shell")
    }

    // A design task is the one thing still handed to a skill, and it gates what waits on it.
    @Test func designTasksGoToTheDesigner() throws {
        let design = NotebookCard(
            id: "design-home", url: URL(fileURLWithPath: "/p/.notebook/tasks/design-home.md"),
            kind: .task, title: "Design the home page", status: "todo", project: nil, dependsOn: [],
            designer: "Allen")
        let brief = NotebookFormat.workPrompt(tasks: [design], sessionID: UUID())
        #expect(
            brief.contains("`designer` skill") || brief.contains("designer skill at"),
            "design work follows the designer skill")
        #expect(brief.contains("until I approve its demo"))
    }

    // A change request with no session left on the task starts a fresh one with the comments.
    @Test func changeRequestCarriesTheComments() throws {
        let task = NotebookCard(
            id: "wire-auth", url: URL(fileURLWithPath: "/p/.notebook/tasks/wire-auth.md"),
            kind: .task, title: "Wire auth", status: "done", project: nil, dependsOn: [])
        let asked = "Changes requested on wire-auth — \"Wire auth\"."
        let brief = NotebookFormat.workPrompt(tasks: [task], sessionID: UUID(), message: asked)
        #expect(brief.contains(asked) && brief.contains("wire-auth"))
        #expect(try echo(AgentCommand.quoted(brief)) == brief, "change request mangled by the shell")
    }

    // Incubate mode: the app writes no agent, the session does — so the prompt is the
    // skill that knows how to search, carrying only what the user typed.
    @Test func incubatePromptCarriesTheDescription() throws {
        let incubate = NotebookFormat.incubatePrompt(
            brief: "An agent that owns database migrations",
            agent: .claude)
        #expect(
            incubate.contains("incubate-agent") && incubate.contains("owns database migrations"),
            "the description reaches the skill that turns it into a roster file")
        let echoed = try echo(AgentCommand.quoted(incubate))
        #expect(echoed == incubate, "incubate brief mangled by the shell")
    }
}
