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
}
