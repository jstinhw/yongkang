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
    private func running(
        _ title: String, in project: ProjectModel, id: UUID = UUID(), taskIDs: [String] = []
    ) -> UUID {
        _ = project.addSession(.claude, id: id, title: title, taskIDs: taskIDs)
        return id
    }

    /// `text` filed as `.notebook/blocks/<slug>.md` in the project, and read back.
    private func block(_ slug: String, _ text: String, in project: ProjectModel) throws -> UserBlock {
        let folder = Blocks.root(in: project.notebookRoot)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(slug).md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return try #require(Blocks.block(at: file))
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

    // MARK: - Product

    @Test func aSecondProductRequestIsTypedIntoTheRunningProductSession() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: [], in: tmp)

        let review = project.startProductReview(agent: .claude)
        let product = try #require(project.sessions.first)
        #expect(product.isProduct && product.line.contains("review"))
        #expect(review == Destination(section: .agents, route: .session(product.id)))

        let describe = project.startProduct("describe", agent: .codex)
        #expect(project.sessions.count == 1, "one product voice per project")
        #expect(describe.route == .session(product.id))
        #expect(
            describe.input?.contains("describe") == true
                && describe.input?.contains(product.id.uuidString.lowercased()) == true,
            "the request is typed in, still naming the session it goes to")

        _ = project.markExited(product.id)
        let fresh = project.startProduct("describe", agent: .codex)
        let second = try #require(project.sessions.last)
        #expect(second.title == "Product 2" && second.agent == .codex, "an exited Product is not talked to")
        #expect(fresh == Destination(section: .agents, route: .session(second.id)))
    }

    @Test func incubatingStartsASessionOnTheBrief() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: [], in: tmp)

        let destination = project.startIncubation("A copy editor for the docs", agent: .claude)
        let session = try #require(project.sessions.first)
        #expect(session.title == "New Agent" && session.line.contains("A copy editor for the docs"))
        #expect(destination == Destination(section: .agents, route: .session(session.id)))
    }

    // MARK: - Blocks

    @Test func unblockingAGateStartsItsOwnSessionAndAProposalGoesBackToProduct() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: [], in: tmp)

        let gate = try block("github-token", try fixture("notebook/c-block-token.md"), in: project)
        let started = project.startUnblock(gate, agent: .claude)
        let unblock = try #require(project.sessions.first)
        #expect(unblock.title == "Unblock GitHub needs a personal access token")
        #expect(started == Destination(section: .agents, route: .session(unblock.id)))

        let proposal = try block("add-checkout", try fixture("notebook/c-proposal-add-checkout.md"), in: project)
        let reopened = project.startUnblock(proposal, agent: .claude)
        let product = try #require(project.sessions.last)
        #expect(product.isProduct, "the Product session it names is gone, so a fresh one picks the proposal up")
        #expect(
            product.line.contains(".notebook/blocks/add-checkout.md") && !product.line.contains("Decision: approve"),
            "a proposal still in discussion is not approved by opening it")
        #expect(reopened == Destination(section: .agents, route: .session(product.id)))
    }

    @Test func approvingAReadyProposalIsTypedIntoTheProductSessionThatShapedIt() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: [], in: tmp)
        let proposal = try block("add-checkout", try fixture("notebook/c-proposal-add-checkout.md"), in: project)
        let shaped = running("Product", in: project, id: try #require(proposal.session))
        let newer = running("Product", in: project)

        #expect(
            project.openProposal(proposal, approve: false, agent: .claude)
                == Destination(section: .agents, route: .session(shaped)),
            "opening is only navigation, to the session the proposal names rather than the newest")
        let approved = project.openProposal(proposal, approve: true, agent: .claude)
        #expect(approved.route == .session(shaped) && approved.input?.hasPrefix("Approved.") == true)
        #expect(project.sessions.count == 2, "nothing new is started while its Product is running")

        _ = project.markExited(shaped)
        #expect(
            project.openProposal(proposal, approve: true, agent: .claude).route == .session(newer),
            "with that one gone, the newest running Product has it")
    }

    /// A demo waiting on the user, made by `session`.
    private func demo(madeBy session: UUID, in project: ProjectModel) throws -> UserBlock {
        try block(
            "hero-demo",
            """
            ---
            id: hero-demo
            kind: demo
            title: "Hero"
            status: open
            session: \(session.uuidString)
            ---

            ## Revisions

            - v1 · three feature columns · http://localhost:3100
            - v2 · one claim, one button · http://localhost:3101
            """, in: project)
    }

    @Test func approvingADemoClearsItsBlockAndTellsTheDesignerWhichRevisionWon() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: [], in: tmp)
        let designer = running("Engineering Lead", in: project)
        let demo = try demo(madeBy: designer, in: project)

        let approved = try #require(project.approveDemo(demo, revision: demo.revisions.last))
        #expect(approved.section == .agents && approved.route == .session(designer))
        #expect(approved.input?.hasPrefix("The demo at hero-demo is approved. Build v2.") == true)
        #expect(Blocks.block(at: demo.url)?.waiting == false, "the block is cleared the way any other is")
    }

    @Test func revisingADemoOpensTheSessionThatMadeIt() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: [], in: tmp)
        let designer = running("Engineering Lead", in: project)
        let demo = try demo(madeBy: designer, in: project)

        #expect(project.openDesigner(demo) == Destination(section: .agents, route: .session(designer)))
        _ = project.markExited(designer)
        #expect(project.openDesigner(demo) == nil, "with nobody waiting on it there is no one to tell")
    }

    // MARK: - Review

    // The model runs git on the main thread, as the app does, and each call that reads the
    // repo is several git processes. These tests yield between those calls: the terminal
    // tests running beside them read their PTY output on the main thread, and a few seconds
    // of git in one stretch runs them past their bound.

    /// Makes `directory` a repository with a committer, off the main thread.
    nonisolated private func repository(_ directory: URL) async throws {
        for arguments in [
            ["init", "--quiet"], ["config", "user.email", "workflow@example.com"], ["config", "user.name", "Workflow"],
        ] {
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            git.arguments = ["git"] + arguments
            git.environment = GitChanges.environment
            git.currentDirectoryURL = directory
            git.standardOutput = FileHandle.nullDevice
            git.standardError = FileHandle.nullDevice
            try git.run()
            git.waitUntilExit()
            try #require(git.terminationStatus == 0, "git \(arguments.joined(separator: " ")) failed")
        }
    }

    @Test func approvingATaskCommitsOnlyItsFilesAndRoutesToTheNextOneWaiting() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: ["Wire auth", "Ship it"], in: tmp)
        try await repository(project.directory)
        for task in ["wire-auth", "ship-it"] {
            let url = try card(task, in: project).url
            let done = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: "status: todo", with: "status: done")
            try done.write(to: url, atomically: true, encoding: .utf8)
            let file = project.directory.appendingPathComponent("\(task).txt")
            try "\(task)\n".write(to: file, atomically: true, encoding: .utf8)
        }
        project.reloadNotebook(frontmatter: true, records: true)
        _ = running("Engineering Lead", in: project, taskIDs: ["wire-auth", "ship-it"])
        project.sessions[0].coordination = LeadCoordination(
            workers: ["wire-auth", "ship-it"].map { LeadWork(id: $0, taskID: $0, paths: ["\($0).txt"], state: "done") })
        project.refreshRepo()
        try #require(project.summary.waiting.count == 2, "both tasks are done and waiting on the user")
        let (first, next) = (project.summary.waiting[0], project.summary.waiting[1])
        project.reviewDrafts[first.id] = ReviewDraft(note: "Looks right")
        project.reviewDrafts[next.id] = ReviewDraft(note: "Not yet")
        await Task.yield()

        #expect(throws: CommitFailure.self, "a blank message is git's refusal, not a route") {
            try project.approve(next, message: "  ")
        }
        #expect(project.reviewDrafts[next.id] != nil, "and a refused approval keeps what the user wrote")
        await Task.yield()

        #expect(try project.approve(first, message: "Approve \(first.title)") == .reviewTask(next.id))
        #expect(project.reviewDrafts[first.id] == nil)
        let left = project.repo.changes.map(\.path)
        #expect(
            !left.contains("\(first.id).txt") && left.contains("\(next.id).txt"),
            "only the approved task's files went in, as the repo read after the commit shows")
    }

    @Test func sendingATaskBackGoesToTheLeadThatHoldsItOrStartsOne() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: ["Wire auth"], in: tmp)
        let task = SummaryTask(id: "wire-auth", title: "Wire auth", status: "done")
        let other = running("Engineering Lead", in: project, taskIDs: ["ship-it"])
        let holder = running("Engineering Lead", in: project, taskIDs: ["wire-auth"])
        #expect(project.requestChanges(on: task, agent: .claude) == nil, "nothing written, nothing to send")

        let draft = ReviewDraft(note: "Handle an expired token")
        let message = draft.message(taskID: task.id, title: task.title)
        project.reviewDrafts[task.id] = draft
        #expect(
            project.requestChanges(on: task, agent: .claude)
                == Destination(section: .agents, route: .session(holder), input: message),
            "the comments go to the lead holding the task, not the first one running")
        #expect(project.reviewDrafts[task.id] == nil, "a draft that was sent is gone")

        _ = project.markExited(holder)
        project.reviewDrafts[task.id] = draft
        #expect(project.requestChanges(on: task, agent: .claude)?.route == .session(other))
        #expect(project.sessions[0].taskIDs == ["ship-it", "wire-auth"], "a lead that takes it over now holds it")

        _ = project.markExited(other)
        project.reviewDrafts[task.id] = draft
        let fresh = try #require(project.requestChanges(on: task, agent: .codex))
        let started = try #require(project.sessions.last)
        #expect(started.isEngineeringLead && started.agent == .codex && started.taskIDs == [task.id])
        #expect(started.line.contains("Handle an expired token"), "a fresh lead starts with the comments")
        #expect(fresh == Destination(section: .agents, route: .session(started.id)))
    }

    @Test func committingTheWorkingTreeRoutesBackToTheReview() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: ["Wire auth"], in: tmp)
        try await repository(project.directory)

        #expect(try project.commit("Add the notebook") == .review(file: nil))
        #expect(
            project.repo.changes.isEmpty && project.repo.head?.hasSuffix("Add the notebook") == true,
            "the new notebook went in, and the repo was read again after")
    }

    // MARK: - Services

    @Test func runningServicesStartsEachOnceAndNamesWhatHasNothingToRun() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try project(tasks: [], in: tmp)
        let (web, api) = (tmp.appendingPathComponent("web"), tmp.appendingPathComponent("api"))
        let steps: [(repo: String, directory: URL, services: [Service.Runnable])] = [
            (repo: "web", directory: web, services: [(name: "web", directory: web, command: "npm run dev")]),
            (
                repo: "api", directory: api,
                services: [
                    (name: "server", directory: api.appendingPathComponent("server"), command: "cargo run"),
                    (name: "worker", directory: api.appendingPathComponent("worker"), command: nil),
                ]
            ),
        ]

        let first = project.runServices(steps)
        #expect(
            project.sessions.map(\.title) == ["Run web", "Run api/server"],
            "a service named after its repo keeps that name; one of several is repo/service")
        #expect(project.sessions[0].line.contains("npm run dev") && project.sessions[0].agent == nil)
        #expect(first.destination == Destination(section: .agents, route: .session(project.sessions[1].id)))
        #expect(first.unstarted == ["api/worker"], "what has nothing to run is named, not skipped")

        let again = project.runServices(steps)
        #expect(project.sessions.count == 2, "a service already running is shown, not started again")
        #expect(again.destination == first.destination)

        let nothing = project.runServices([
            (repo: "docs", directory: tmp, services: [(name: "docs", directory: tmp, command: nil)])
        ])
        #expect(nothing.destination == Destination(section: .agents) && nothing.unstarted == ["docs"])
    }

    // MARK: - Notebook

    /// A project with a `launch` project holding the `wire-auth` task, and a loose `other` task.
    private func launch(in tmp: URL) throws -> ProjectModel {
        let directory = tmp.appendingPathComponent("app")
        let root = NotebookFormat.root(in: directory)
        _ = try NotebookFormat.create(.project, title: "Launch", in: root, project: nil)
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch")
        _ = try NotebookFormat.create(.task, title: "Other", in: root, project: nil)
        let project = ProjectModel(directory: directory)
        project.reloadNotebook(frontmatter: true, records: true)
        return project
    }

    @Test func addingAnEntryFilesItUnderTheSelectionAndOpensItsPage() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try launch(in: tmp)
        #expect(project.notebookProject(for: .task("wire-auth")) == "launch", "a task sits in its own project")
        #expect(project.notebookProject(for: .board) == nil)

        #expect(
            try project.add(.task, title: "Ship it", selection: .project("launch"))
                == Destination(section: .board, route: .task("ship-it")))
        let memory = try project.add(.memory, title: "Token lifetimes", selection: .task("wire-auth"))
        #expect(
            try project.add(.project, title: "Checkout", selection: nil)
                == Destination(section: .board, route: .project("checkout")),
            "a project opens by its folder's name")
        #expect(throws: NotebookError.self, "memory with no project to sit in is refused") {
            try project.add(.memory, title: "Loose note", selection: .board)
        }

        project.reloadNotebook(frontmatter: true, records: true)
        #expect(try card("ship-it", in: project).project == "launch")
        let page = try card(try #require(memory.route?.cardID), in: project)
        #expect(memory == Destination(section: .board, route: .page(page.id)))
        #expect(
            page.kind == .memory && page.project == "launch" && page.subject == "wire-auth",
            "memory added on a task lands in the task's project, about that task")
    }

    @Test func removingAProjectTakesItsTasksAndLeavesAPageThatWentWithIt() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try launch(in: tmp)
        let asked = project.snapshot.cards
        let (other, launch) = (try card("other", in: project), try card("launch", in: project))
        // An agent files another task under the project while the user is being asked.
        _ = try NotebookFormat.create(.task, title: "Late", in: project.notebookRoot, project: "launch")

        #expect(
            try project.remove(other, from: asked, selection: .task("wire-auth"), trash: false) == nil,
            "the page on screen is still there, so the selection stays")
        #expect(
            try project.remove(launch, from: asked, selection: .task("wire-auth"), trash: false) == .board,
            "the task on screen went with its project")
        project.reloadNotebook(frontmatter: true, records: true)
        #expect(
            project.snapshot.cards.map(\.id) == ["late"],
            "what goes is what the user confirmed: a task filed since is left for them to see")
    }
}
