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

    // Picked tasks reach the lead as links, without duplicating their page descriptions.
    @Test func pickedTasksReachTheLeadAsLinks() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let picked = try pickedTasks(in: tmp)
        try #require(picked.count >= 2)
        let leadID = UUID()
        let brief = NotebookFormat.engineeringPrompt(tasks: picked, sessionID: leadID, agent: .claude)

        #expect(
            brief.contains(leadID.uuidString.lowercased()),
            "a lead has to know its own session id to route a block's answer back")
        #expect(brief.contains("engineering-lead"), "task batches invoke the dispatcher skill")
        for task in picked {
            #expect(brief.contains(task.id) && !brief.contains(task.title))
            #expect(
                brief.contains(".notebook/tasks/\(task.url.deletingPathExtension().lastPathComponent).md"),
                "the lead needs a path it can open from the project root")
        }
        #expect(
            brief.contains("Session id: \(leadID.uuidString.lowercased())"),
            "the lead needs its session id for blocks")
        let echoed = try echo(AgentCommand.quoted(brief))
        #expect(echoed == brief, "task brief mangled by the shell")
    }

    // A follow-up batch reinvokes the same dispatcher with the same task detail.
    @Test func followUpBatchUsesTheSameDispatcher() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let picked = try pickedTasks(in: tmp)
        let follow = NotebookFormat.additionalTasksPrompt(tasks: picked, sessionID: UUID(), agent: .claude)

        for task in picked {
            #expect(follow.contains(task.id) && !follow.contains(task.title))
        }
        #expect(follow.contains("engineering-lead"), "follow-ups use the dispatcher skill too")
    }

    // The always-on lead: an empty batch is a standby brief, still carrying the id.
    @Test func emptyBatchIsAStandbyBrief() throws {
        let leadID = UUID()
        let standby = NotebookFormat.engineeringPrompt(tasks: [], sessionID: leadID, agent: .claude)
        #expect(
            standby.contains("engineering-lead") && standby.contains("stand by"),
            "no tasks means the lead confirms the team and waits")
        #expect(standby.contains("Session id: \(leadID.uuidString.lowercased())"))
        let echoed = try echo(AgentCommand.quoted(standby))
        #expect(echoed == standby, "standby brief mangled by the shell")
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
