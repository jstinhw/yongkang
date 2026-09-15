import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// What each button leaves behind: the sessions it starts, what it types into a running one,
/// and where the window goes. The workflows only return the destination, so no view or PTY
/// is involved; a session here is a row with a command line nobody runs.
@Suite @MainActor struct WorkflowTests {
    /// A project in `tmp` whose notebook holds a task per title, read the way the poll reads it.
    private func project(tasks titles: [String], in tmp: URL) throws -> ProjectModel {
        let directory = tmp.appendingPathComponent("app")
        for title in titles {
            _ = try NotebookFormat.create(.task, title: title, in: NotebookFormat.root(in: directory), project: nil)
        }
        let project = ProjectModel(directory: directory)
        project.reloadNotebook(frontmatter: true, records: true)
        return project
    }

    private func card(_ id: String, in project: ProjectModel) throws -> NotebookCard {
        try #require(project.snapshot.cards.first { $0.id == id })
    }

    /// A running session with `title`, the way a workflow would have started it.
    private func running(_ title: String, in project: ProjectModel, taskIDs: [String] = []) -> UUID {
        let id = UUID()
        _ = project.addSession(.claude, id: id, title: title, taskIDs: taskIDs)
        return id
    }

    // MARK: - Assign

    @Test func assigningWithNoLeadStartsOneOnTheBatchAndItsBlockers() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: ["Wire auth", "Ship it"], in: tmp)
        let shipIt = try card("ship-it", in: project)
        let text = try String(contentsOf: shipIt.url, encoding: .utf8)
            .replacingOccurrences(of: "depends_on: []", with: "depends_on: [wire-auth]")
        try text.write(to: shipIt.url, atomically: true, encoding: .utf8)
        project.reloadNotebook(frontmatter: true, records: true)

        let destination = try #require(project.assign([try card("ship-it", in: project)], agent: .codex))
        let lead = try #require(project.sessions.first)
        #expect(lead.isEngineeringLead && lead.agent == .codex, "a new lead, on the provider picked in the top bar")
        #expect(Set(lead.taskIDs) == ["wire-auth", "ship-it"], "the blocker comes along with the task picked")
        #expect(destination == Destination(section: .agents, route: .session(lead.id)))
        #expect(lead.line.contains(lead.id.uuidString.lowercased()), "the prompt names the session it starts")
    }

    @Test func assigningToARunningLeadQueuesAFollowUpAndRoutesToItsSession() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: ["Wire auth", "Ship it"], in: tmp)
        let lead = running("Engineering Lead", in: project, taskIDs: ["wire-auth"])

        let destination = try #require(project.assign([try card("ship-it", in: project)], agent: .claude))
        #expect(project.sessions.count == 1, "the running lead is talked to, not duplicated")
        #expect(project.sessions[0].taskIDs == ["wire-auth", "ship-it"])
        #expect(destination.section == .agents && destination.route == .session(lead))
        #expect(destination.input?.contains("Task id: ship-it") == true, "the new batch is typed into its terminal")

        #expect(
            project.assign([try card("wire-auth", in: project)], agent: .claude) == nil,
            "a task a lead already holds is not assigned again, and there is nowhere to go")
        #expect(project.assign([], agent: .claude) == nil)
    }
}
