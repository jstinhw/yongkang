import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// What each button leaves behind: the sessions it starts, what it types into a running one,
/// and where the window goes. The workflows only return the destination, so no view or PTY
/// is involved; a session here is a row with a command line nobody runs.
@Suite @MainActor struct WorkflowTests {
    /// A project in `tmp` whose notebook holds a task per title, read the way the poll reads it.
    private func project(tasks titles: [String], in tmp: URL) async throws -> ProjectModel {
        let directory = tmp.appendingPathComponent("app")
        for title in titles {
            _ = try NotebookFormat.create(.task, title: title, in: NotebookFormat.root(in: directory), project: nil)
        }
        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)
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

    @Test func assigningStartsOneSessionOnTheTaskAndItsBlockers() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth", "Ship it"], in: tmp)
        let shipIt = try card("ship-it", in: project)
        let text = try String(contentsOf: shipIt.url, encoding: .utf8)
            .replacingOccurrences(of: "depends_on: []", with: "depends_on: [wire-auth]")
        try text.write(to: shipIt.url, atomically: true, encoding: .utf8)
        await project.reloadNotebook(frontmatter: true, records: true)

        let destination = try #require(project.assign([try card("ship-it", in: project)], agent: .codex))
        let session = try #require(project.sessions.first)
        #expect(project.sessions.count == 1, "a task and its blocker are one chain, so one session")
        #expect(session.holdsTasks && session.agent == .codex, "on the agent picked beside the button")
        #expect(session.taskIDs == ["wire-auth", "ship-it"], "the blocker comes along, and goes first")
        #expect(destination == Destination(section: .agents, route: .session(session.id)))
        #expect(session.line.contains(session.id.uuidString.lowercased()), "the prompt names the session")
    }

    @Test func anAgentGivenAnotherRepoIsLaunchedWithItAndToldToLeaveItAlone() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let other = tmp.appendingPathComponent("api")

        _ = project.assign([try card("wire-auth", in: project)], agent: .claude, reading: [other])
        let session = try #require(project.sessions.first)
        #expect(session.reading == [other], "the session keeps the folder it was given")
        #expect(session.line.contains("--add-dir '\(other.path)'"), "Claude Code is handed the folder")
        #expect(session.line.contains("Change nothing there"), "and told it is for reading")

        // The same notebook, read fresh, so the task has no session yet.
        let grok = try await self.project(tasks: [], in: tmp)
        _ = grok.assign([try card("wire-auth", in: grok)], agent: .grok, reading: [other])
        #expect(grok.sessions.first?.reading == [], "Grok takes no folder beside its own, so it is given none")
    }

    @Test func twoTasksThatWaitOnNothingStartTwoSessions() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth", "Ship it"], in: tmp)

        let destination = try #require(
            project.assign([try card("wire-auth", in: project), try card("ship-it", in: project)], agent: .claude))
        #expect(project.sessions.count == 2, "independent work is not queued behind one agent")
        #expect(
            project.sessions.map(\.taskIDs) == [["ship-it"], ["wire-auth"]],
            "one session per task, in the notebook's order, each prompted for its own")
        #expect(
            project.sessions.map(\.title) == ["Claude Code", "Claude Code 2"],
            "named after the coding agent, with the tasks listed under it by their own names")
        #expect(
            destination == Destination(section: .agents, route: .agents),
            "the project's Agents page shows both, even with the sidebar hidden")
    }

    // Every CLI asks whether it may work in a folder before anything else, in every session.
    @Test func anAgentNotYetAllowedInTheFolderIsAskedOnceBeforeAnyWork() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        var allowed = false
        project.trustRecord = { agent, _ in agent == .claude ? allowed : true }

        await project.readTrust(Set(AgentKind.allCases))
        #expect(project.untrusted == [.claude], "only the CLI whose record says no")
        #expect(project.askToTrust(.codex) == nil, "one that is allowed has nothing to ask")
        let destination = try #require(project.askToTrust(.claude))
        let asking = try #require(project.sessions.first)
        #expect(destination == Destination(section: .agents, route: .session(asking.id)), "the window opens on it")
        #expect(asking.agent == .claude && !asking.holdsTasks, "a session with no work, only the question")
        #expect(project.askToTrust(.claude) == nil, "the session already asking is the one to answer")

        #expect(await !project.trustGranted(by: asking.id), "still no: the answer was not yes")
        allowed = true
        let other = running("Product", in: project)
        #expect(await !project.trustGranted(by: other), "another session's answer lets it in, but closes nothing")
        #expect(project.untrusted.isEmpty)
        #expect(await project.trustGranted(by: asking.id), "the session that asked is done")
        #expect(project.trustSession == nil)
    }

    // A record Yongkang misreads, or one the CLI lost, must not leave the work unable to start.
    @Test func aSessionOpenedToAskThatAsksNothingLetsItsAgentIn() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        project.trustRecord = { _, _ in false }
        await project.readTrust([.agy])
        #expect(!project.trustReadIsDue(), "a record is read at most every 30 s")
        #expect(project.trustReadIsDue(now: Date().addingTimeInterval(31)))

        _ = try #require(project.askToTrust(.agy))
        let id = try #require(project.sessions.first).id
        #expect(!project.trustSettled(by: id, asking: true), "still asking, so the user is still to answer")
        #expect(project.trustSettled(by: id, asking: false), "up and asking nothing, so there is nothing to ask")
        #expect(project.untrusted.isEmpty && project.trustSession == nil)
        await project.readTrust([.agy])
        #expect(project.untrusted.isEmpty, "let in for the rest of the run, whatever the record says")
    }

    @Test func assigningAgainStartsItsOwnSessionOnItsOwnAgent() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth", "Ship it"], in: tmp)
        let first = running("Wire auth", in: project, taskIDs: ["wire-auth"])

        let destination = try #require(project.assign([try card("ship-it", in: project)], agent: .codex))
        let second = try #require(project.sessions.last)
        #expect(second.id != first, "a running session is never handed more work")
        #expect(second.agent == .codex && second.taskIDs == ["ship-it"] && second.title == "Codex")
        #expect(destination == Destination(section: .agents, route: .session(second.id)))

        #expect(
            project.assign([try card("wire-auth", in: project)], agent: .claude) == nil,
            "a task a session already holds is not assigned again, and there is nowhere to go")
        #expect(project.assign([], agent: .claude) == nil)
    }

    // MARK: - Product

    @Test func aSecondProductRequestIsTypedIntoTheRunningProductSession() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: [], in: tmp)

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

    @Test func incubatingStartsASessionOnTheBrief() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: [], in: tmp)

        let destination = project.startIncubation("A copy editor for the docs", agent: .claude)
        let session = try #require(project.sessions.first)
        #expect(session.title == "New Agent" && session.line.contains("A copy editor for the docs"))
        #expect(destination == Destination(section: .agents, route: .session(session.id)))
    }

    // MARK: - Blocks

    @Test func unblockingAGateStartsItsOwnSessionAndAProposalGoesBackToProduct() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: [], in: tmp)

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

    @Test func aSetupSessionIsFinishedOnceItsPlanIsDone() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: [], in: tmp)
        // Agy keeps no transcript, so the draft alone decides.
        _ = project.startNotebookSetup("a site", agent: .agy)
        let setup = try #require(project.sessions.first).id
        let product = running("Product", in: project)
        let plan = { (session: UUID, status: String) in
            "---\nkind: proposal\ntitle: Plan\nstatus: \(status)\nsession: \(session)\n---\n"
        }
        _ = try block("plan", plan(setup, "open"), in: project)
        _ = try block("add-checkout", plan(product, "done"), in: project)
        await project.reloadNotebook(frontmatter: true, records: true)
        #expect(
            await project.finishedSetups().isEmpty,
            "a plan still open is still being talked through, and Product outlives the plans it writes")

        _ = try block("plan", plan(setup, "done"), in: project)
        await project.reloadNotebook(frontmatter: true, records: true)
        #expect(await project.finishedSetups().map(\.id) == [setup], "the notebook is written, so setup is over")
    }

    @Test func approvingAReadyProposalIsTypedIntoTheProductSessionThatShapedIt() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: [], in: tmp)
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
            task: design-hero
            session: \(session.uuidString)
            ---

            ## Revisions

            - v1 · three feature columns · http://localhost:3100
            - v2 · one claim, one button · http://localhost:3101
            """, in: project)
    }

    @Test func approvingADemoClearsItsBlockAndTellsTheDesignerWhichRevisionWon() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Design hero"], in: tmp)
        let designer = running("Engineering Lead", in: project)
        let demo = try demo(madeBy: designer, in: project)

        let approved = try #require(project.approveDemo(demo, revision: demo.revisions.last, agent: .claude))
        #expect(approved.section == .agents && approved.route == .session(designer))
        #expect(approved.input?.hasPrefix("The demo at hero-demo is approved. Build v2.") == true)
        #expect(Blocks.block(at: demo.url)?.waiting == false, "the block is cleared the way any other is")
        #expect(
            project.deliveredBlocks.contains(demo.id),
            "and counts as delivered, so the poll doesn't tell the designer Unblocked on top")
    }

    @Test func revisingADemoSendsWhatTheUserWroteToTheSessionThatMadeIt() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Design hero"], in: tmp)
        let designer = running("Engineering Lead", in: project)
        let demo = try demo(madeBy: designer, in: project)
        project.reviewDrafts[demo.id] = ReviewDraft(note: "Too dense. Cut the third column.")

        #expect(
            project.requestDemoChanges(demo, note: " \n ", agent: .claude) == nil,
            "nothing written, nothing sent — the button says so instead")
        let sent = try #require(
            project.requestDemoChanges(demo, note: "Too dense. Cut the third column.", agent: .claude))
        #expect(sent.section == .agents && sent.route == .session(designer))
        #expect(sent.input?.contains("Too dense. Cut the third column.") == true)
        #expect(sent.input?.contains("the next pass on that demo, not the task again") == true)
        #expect(project.sessions.count == 1, "a further pass is not a new session")
        #expect(Blocks.block(at: demo.url)?.waiting == true, "the demo stays open for the pass that answers it")
        #expect(project.reviewDrafts[demo.id] == nil, "and what they wrote is spent")
    }

    // A demo waits for as long as the user takes to look at it, which outlives the session
    // that built it. Neither answer may be a button that does nothing.
    @Test func decidingADemoAfterItsSessionExitedStartsTheDesignTaskAgain() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Design hero"], in: tmp)
        let designer = running("Engineering Lead", in: project)
        let demo = try demo(madeBy: designer, in: project)
        _ = project.markExited(designer)

        let revise = try #require(project.requestDemoChanges(demo, note: "Cut the third column.", agent: .codex))
        let started = try #require(project.sessions.last)
        #expect(revise == Destination(section: .agents, route: .session(started.id)))
        #expect(started.taskIDs == ["design-hero"] && started.agent == .codex)
        #expect(
            started.line.contains("Cut the third column.")
                && started.line.contains("not the task again"),
            "the new agent is pointed at the demo it continues, with what the user wrote")

        let approved = try #require(project.approveDemo(demo, revision: nil, agent: .claude))
        #expect(approved != revise, "approving after that starts its own session, not the same one")
        #expect(project.sessions.last?.line.contains("is approved") == true)
    }

    // MARK: - Review

    /// Makes `directory` a repository with a committer. With the app's git environment, so a
    /// test run from a git hook never touches the checkout running it.
    private func repository(_ directory: URL) async throws {
        for arguments in [
            ["init", "--quiet"], ["config", "user.email", "workflow@example.com"], ["config", "user.name", "Workflow"],
        ] {
            let git = try await AsyncProcess.run(
                URL(fileURLWithPath: "/usr/bin/env"), ["git"] + arguments, in: directory,
                environment: GitClient.environment)
            try #require(git.status == 0, "git \(arguments.joined(separator: " ")) failed")
        }
    }

    @Test func approvingATaskCommitsOnlyItsFilesAndRoutesToTheNextOneWaiting() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth", "Ship it"], in: tmp)
        try await repository(project.directory)
        for task in ["wire-auth", "ship-it"] {
            let url = try card(task, in: project).url
            let done = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: "status: todo", with: "status: done")
            try done.write(to: url, atomically: true, encoding: .utf8)
            let file = project.directory.appendingPathComponent("\(task).txt")
            try "\(task)\n".write(to: file, atomically: true, encoding: .utf8)
        }
        await project.reloadNotebook(frontmatter: true, records: true)
        _ = running("Engineering Lead", in: project, taskIDs: ["wire-auth", "ship-it"])
        project.sessions[0].coordination = LeadCoordination(
            workers: ["wire-auth", "ship-it"].map { LeadWork(id: $0, taskID: $0, paths: ["\($0).txt"], state: "done") })
        await project.refreshRepo()
        try #require(project.summary.waiting.count == 2, "both tasks are done and waiting on the user")
        let (first, next) = (project.summary.waiting[0], project.summary.waiting[1])
        project.reviewDrafts[first.id] = ReviewDraft(note: "Looks right")
        project.reviewDrafts[next.id] = ReviewDraft(note: "Not yet")

        await #expect(throws: CommitFailure.self, "a blank message is git's refusal, not a route") {
            try await project.approve(next, message: "  ")
        }
        #expect(project.reviewDrafts[next.id] != nil, "and a refused approval keeps what the user wrote")

        #expect(try await project.approve(first, message: "Approve \(first.title)") == .reviewTask(next.id))
        #expect(project.reviewDrafts[first.id] == nil)
        let left = project.repo.changes.map(\.path)
        #expect(
            !left.contains("\(first.id).txt") && left.contains("\(next.id).txt"),
            "only the approved task's files went in, as the repo read after the commit shows")
    }

    @Test func sendingATaskBackGoesToTheSessionThatHoldsItOrStartsOne() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        let task = SummaryTask(id: "wire-auth", title: "Wire auth", status: "done")
        let other = running("Ship it", in: project, taskIDs: ["ship-it"])
        let holder = running("Wire auth", in: project, taskIDs: ["wire-auth"])
        #expect(project.requestChanges(on: task, agent: .claude) == nil, "nothing written, nothing to send")

        let draft = ReviewDraft(note: "Handle an expired token")
        let message = draft.message(taskID: task.id, title: task.title)
        project.reviewDrafts[task.id] = draft
        #expect(
            project.requestChanges(on: task, agent: .claude)
                == Destination(section: .agents, route: .session(holder), input: message),
            "the comments go to the session holding the task, not the first one running")
        #expect(project.reviewDrafts[task.id] == nil, "a draft that was sent is gone")

        _ = project.markExited(holder)
        project.reviewDrafts[task.id] = draft
        let fresh = try #require(project.requestChanges(on: task, agent: .codex))
        let started = try #require(project.sessions.last)
        #expect(
            started.id != other && started.holdsTasks && started.agent == .codex && started.taskIDs == [task.id],
            "a session on other work is not handed it; a fresh one starts")
        #expect(started.line.contains("Handle an expired token"), "a fresh session starts with the comments")
        #expect(fresh == Destination(section: .agents, route: .session(started.id)))
    }

    @Test func committingTheWorkingTreeRoutesBackToTheReview() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: ["Wire auth"], in: tmp)
        try await repository(project.directory)

        #expect(try await project.commit("Add the notebook") == .review(file: nil))
        #expect(
            project.repo.changes.isEmpty && project.repo.head?.hasSuffix("Add the notebook") == true,
            "the new notebook went in, and the repo was read again after")
    }

    // MARK: - Services

    @Test func runningServicesStartsEachOnceAndNamesWhatHasNothingToRun() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await project(tasks: [], in: tmp)
        let (web, api) = (tmp.appendingPathComponent("web"), tmp.appendingPathComponent("api"))
        let steps: [ServicePlan] = [
            ServicePlan(
                card: "p", repo: "web", directory: web, exists: true,
                services: [(name: "web", directory: web, command: "npm run dev", frontend: true)]),
            ServicePlan(
                card: "p", repo: "api", directory: api, exists: true,
                services: [
                    (
                        name: "server", directory: api.appendingPathComponent("server"),
                        command: "cargo run", frontend: false
                    ),
                    (
                        name: "worker", directory: api.appendingPathComponent("worker"),
                        command: nil, frontend: false
                    ),
                ]),
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
            ServicePlan(
                card: "p", repo: "docs", directory: tmp, exists: true,
                services: [(name: "docs", directory: tmp, command: nil, frontend: false)])
        ])
        #expect(nothing.destination == Destination(section: .agents) && nothing.unstarted == ["docs"])
    }

    // MARK: - Notebook

    /// A project with a `launch` project holding the `wire-auth` task, and a loose `other` task.
    private func launch(in tmp: URL) async throws -> ProjectModel {
        let directory = tmp.appendingPathComponent("app")
        let root = NotebookFormat.root(in: directory)
        _ = try NotebookFormat.create(.project, title: "Launch", in: root, project: nil)
        _ = try NotebookFormat.create(.task, title: "Wire auth", in: root, project: "launch")
        _ = try NotebookFormat.create(.task, title: "Other", in: root, project: nil)
        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)
        return project
    }

    @Test func addingAnEntryFilesItUnderTheSelectionAndOpensItsPage() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await launch(in: tmp)
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

        await project.reloadNotebook(frontmatter: true, records: true)
        #expect(try card("ship-it", in: project).project == "launch")
        guard case .memory(let id?)? = memory.route else {
            Issue.record("memory opens on the Memory page, on itself")
            return
        }
        let page = try card(id, in: project)
        #expect(memory == Destination(section: .agents, route: .memory(page.id)))
        #expect(
            page.kind == .memory && page.project == "launch" && page.subject == "wire-auth",
            "memory added on a task lands in the task's project, about that task")
    }

    @Test func removingAProjectTakesItsTasksAndLeavesAPageThatWentWithIt() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await launch(in: tmp)
        let model = AppModel()
        model.selection = .task("wire-auth")
        let (other, launch) = (try card("other", in: project), try card("launch", in: project))

        model.remove(other, in: project, trash: false)
        #expect(model.alert?.detail == "You can put it back from the Trash.")
        try answer(model)
        #expect(model.selection == .task("wire-auth"), "the page on screen is still there, so the selection stays")

        model.remove(launch, in: project, trash: false)
        #expect(model.alert?.title == "Move \u{201C}Launch\u{201D} to the Trash?")
        #expect(model.alert?.detail.hasPrefix("The project folder, its memory and its 1 task go with it.") == true)
        // An agent files another task under the project while the user is being asked, and the
        // poll reads it.
        _ = try NotebookFormat.create(.task, title: "Late", in: project.notebookRoot, project: "launch")
        await project.reloadNotebook(frontmatter: true, records: true)
        try answer(model)
        #expect(model.selection == .board, "the task on screen went with its project")
        await project.reloadNotebook(frontmatter: true, records: true)
        #expect(
            project.snapshot.cards.map(\.id) == ["late"],
            "what goes is what the user confirmed: a task filed since is left for them to see")
    }

    // MARK: - Alerts

    /// Picks what the alert's main button would: the action of a confirmation, or Create with
    /// `typed` in a title prompt.
    private func answer(_ model: AppModel, typing typed: String = "") throws {
        switch try #require(model.alert, "a question was asked") {
        case .confirm(_, _, _, let perform): perform()
        case .title(_, let create): create(typed)
        case .message(let title, _): Issue.record("\(title) has nothing to answer")
        }
    }

    @Test func whatTheUserHasToReadOrAnswerIsTheModelsAlert() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try await launch(in: tmp)
        let model = AppModel()

        model.assign([], in: project, agent: .claude)
        #expect(model.alert == nil, "no tasks picked is nothing to explain")
        _ = running("Engineering Lead", in: project, taskIDs: ["wire-auth"])
        model.assign([try card("wire-auth", in: project)], in: project, agent: .claude)
        #expect(model.alert?.title == "Nothing to assign")

        model.runServices(
            [
                ServicePlan(
                    card: "p", repo: "docs", directory: tmp, exists: true,
                    services: [(name: "docs", directory: tmp, command: nil, frontend: false)])
            ], in: project)
        #expect(model.alert?.title == "Nothing to run yet")
        #expect(model.alert?.detail.hasPrefix("No start command found in: docs.") == true)

        model.selection = .task("wire-auth")
        model.add(.memory, to: project)
        #expect(model.alert?.title == "New Memory")
        model.selection = .board  // The poll moves on while the user types.
        try answer(model, typing: "  Token lifetimes ")
        await project.reloadNotebook(frontmatter: true, records: true)
        let memory = try #require(project.snapshot.cards.first { $0.kind == .memory })
        #expect(
            memory.title == "Token lifetimes" && memory.project == "launch",
            "filed under what was selected when the user asked")
        #expect(model.selection == .memory(memory.id))

        model.add(.memory, to: project)
        try answer(model, typing: "Loose note")
        #expect(
            model.alert?.title == NotebookError.missingProject.localizedDescription,
            "a failure is the next alert, not a modal")
    }
}
