import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// Relaunching lands you back where you were: the project, its section, and the page it had
/// open. What matters is the failing case — a route naming a card an agent deleted, or a
/// session that died with the app — which has to open the section's own default rather than
/// an empty screen.
@Suite @MainActor struct RestorationTests {
    private func project(tasks titles: [String], in tmp: URL) async throws -> ProjectModel {
        let directory = tmp.appendingPathComponent("app")
        for title in titles {
            _ = try NotebookFormat.create(.task, title: title, in: NotebookFormat.root(in: directory), project: nil)
        }
        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)
        return project
    }

    /// `text` filed as `.notebook/blocks/<slug>.md`, the way an agent raises one.
    private func block(_ slug: String, _ text: String, in project: ProjectModel) throws {
        let folder = Blocks.root(in: project.notebookRoot)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("\(slug).md"), atomically: true, encoding: .utf8)
    }

    /// An `AppModel` holding `project` as an open folder, without entering it — the state
    /// `RootView.restore()` is in once `@AppStorage("openProjects")` has been read back.
    private func reopened(_ project: ProjectModel) -> AppModel {
        let model = AppModel()
        _ = model.open(project.directory)
        return model
    }

    // MARK: - The string a scene keeps

    @Test func aRouteSurvivesBeingWrittenDownAndReadBack() {
        let session = UUID()
        let routes: [Route] = [
            .board, .usage, .project("checkout"), .task("wire-auth"), .page("q3"),
            .entry("tasks/wire-auth"), .session(session), .session(session, pane: .transcript),
            .subagent(session: session, id: "a1"), .block("blocks/needs-a-key.md"),
            .member("David"), .review(file: nil), .review(file: "Sources/App.swift"),
            .reviewTask("wire-auth"), .preview(URL(fileURLWithPath: "/tmp/app")),
        ]
        for route in routes {
            #expect(Route(stored: route.stored) == route, "\(route) came back as something else")
        }
    }

    @Test func aStoredRouteThatNoLongerParsesIsNoRoute() {
        #expect(Route(stored: "") == nil, "a scene that has never stored one")
        #expect(Route(stored: "{\"task\":") == nil, "truncated")
        #expect(Route(stored: "{\"lane\":{\"_0\":\"x\"}}") == nil, "a case this version no longer has")
    }

    // MARK: - Coming back

    @Test func theWindowComesBackOnThePageItLeft() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let model = reopened(project)
        await model.reloadNow()

        model.restore(entered: project.directory.path, section: .board, route: .task("wire-auth"))
        #expect(model.entered?.directory == project.directory)
        #expect(model.section == .board)
        #expect(model.selection == .task("wire-auth"))
    }

    @Test func aFolderThatIsNoLongerOpenLeavesNothingPicked() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let model = reopened(project)
        await model.reloadNow()

        model.restore(entered: "/nowhere/at/all", section: .board, route: .task("wire-auth"))
        #expect(model.entered == nil, "nothing to enter, so the fleet screen — not a project picked at random")
        model.restore(entered: "", section: .board, route: nil)
        #expect(model.entered == nil, "and a first launch, which has stored nothing, is the same case")
    }

    // MARK: - Stale routes

    @Test func aCardAnAgentDeletedOpensTheSectionsDefault() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let model = reopened(project)
        await model.reloadNow()

        model.restore(entered: project.directory.path, section: .board, route: .task("deleted-while-away"))
        #expect(model.section == .board, "the section is still where you were")
        #expect(model.selection == .board, "and the board itself, not a blank work area")
    }

    @Test func aSessionThatDiedWithTheAppOpensTheSectionsDefault() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let model = reopened(project)
        await model.reloadNow()
        let entered = try #require(model.projects.first)
        #expect(!model.restorable(.session(UUID()), in: entered), "no agent outlives the app")

        model.restore(entered: project.directory.path, section: .agents, route: .session(UUID()))
        #expect(model.section == .agents)
        #expect(model.selection == .agents, "the project's agents — the same screen entering the project gives")
    }

    /// A crash keeps the agent and the task it holds: without the task id, its finished work
    /// would drop out of Review as unclaimed files.
    @Test func anAgentOnATaskComesBackAfterACrash() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let first = reopened(project)
        var saved = ""
        first.sessionsChanged = { saved = first.storedSessions }
        let id = UUID()
        first.projects[0].addSession(
            id: id, title: "Claude Code", icon: "sparkles", line: "true", agent: .claude, taskIDs: ["wire-auth"])
        first.terminals.terminate(id)

        let second = reopened(project)
        await second.resumeSessions(saved)
        let entered = try #require(second.projects.first)
        let back = try #require(entered.sessions.first)
        defer { second.terminals.terminate(id) }
        #expect(back.id == id && back.taskIDs == ["wire-auth"] && back.agent == .claude)
        #expect(back.line == "true", "a Claude session with no transcript yet starts over")
        #expect(second.restorable(.session(id), in: entered))
    }

    @Test func aResolvedBlockFallsBackToTheProjectsAgents() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        try block(
            "needs-a-key",
            """
            ---
            kind: block
            title: Needs an API key
            status: waiting
            ---
            Paste the key.
            """, in: project)
        let model = reopened(project)
        await model.reloadNow()
        let entered = try #require(model.projects.first)
        let waiting = try #require(entered.snapshot.blocks.first)

        model.restore(entered: project.directory.path, section: .agents, route: .block("blocks/gone.md"))
        #expect(model.section == .agents)
        #expect(model.selection == .agents, "the project's agents, not an empty pane")
        #expect(
            entered.value.agentRows(summary: entered.summary).first?.route == .block(waiting.id),
            "where the block still waiting on you is the first card")
    }

    /// The same guard from the other side: a block that is still there is what stays open,
    /// even though the section's default would have picked a different one.
    @Test func aBlockStillOnDiskIsTheOneThatOpens() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        for (slug, title) in [("needs-a-key", "Needs an API key"), ("pick-a-host", "Pick a host")] {
            try block(
                slug,
                """
                ---
                kind: block
                title: \(title)
                status: waiting
                ---
                Answer, please.
                """, in: project)
        }
        let model = reopened(project)
        await model.reloadNow()
        let entered = try #require(model.projects.first)
        let second = try #require(entered.snapshot.blocks.last)
        #expect(entered.snapshot.blocks.count == 2)

        model.restore(entered: project.directory.path, section: .agents, route: .block(second.id))
        #expect(model.selection == .block(second.id), "the one you were reading, not the first one waiting")
        // And switching sections away and back lands on the project's agents, because nothing
        // under Agents is open then.
        model.section = .board
        model.openSectionDefault()
        model.section = .agents
        model.openSectionDefault()
        #expect(model.selection == .agents)
    }
}
