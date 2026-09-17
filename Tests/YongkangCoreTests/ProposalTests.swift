import Foundation
import Testing

@testable import YongkangCore

// A proposal shares the folder, the list and the button — it differs in who the
// button reaches, and in that nothing is sitting blocked behind it.
@Suite struct ProposalTests {
    /// The session the fixtures name as the Product transcript waiting on them.
    private let leadID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// A blocks folder holding the proposal, and the gate beside it, as fixtures write them.
    private func blocksRoot(in project: URL) throws -> URL {
        let root = NotebookFormat.root(in: project)
        let blocks = Blocks.root(in: root)
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        try fixture("notebook/c-block-token.md")
            .write(to: blocks.appendingPathComponent("github-token.md"), atomically: true, encoding: .utf8)
        try fixture("notebook/c-proposal-add-checkout.md")
            .write(to: blocks.appendingPathComponent("add-checkout.md"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func discussionProposalReachesProduct() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = try blocksRoot(in: tmp)

        let proposal = try #require(Blocks.load(root: root).first { $0.isProposal })
        #expect(
            proposal.waiting && proposal.session == leadID && !proposal.proposalReady,
            "a discussion notification links back to its Product transcript")
        let approval = NotebookFormat.unblockPrompt(block: proposal, agent: .claude)
        #expect(
            approval.contains("product") && approval.contains(".notebook/blocks/add-checkout.md"),
            "a proposal can be resumed by product, not an engineer")
        #expect(approval.contains("`flowchart LR`"), "a reopened proposal still shows its plan as a graph")
    }

    @Test func onlyAFinalizedProposalIsReady() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = try blocksRoot(in: tmp)
        let proposal = try #require(Blocks.load(root: root).first { $0.isProposal })

        let readyText = try String(contentsOf: proposal.url, encoding: .utf8)
            .replacingOccurrences(of: "stage: discussion", with: "stage: ready")
        try readyText.write(to: proposal.url, atomically: true, encoding: .utf8)
        let ready = try #require(Blocks.load(root: root).first { $0.isProposal })
        #expect(ready.proposalReady, "only a finalized proposal offers project creation")
    }

    @Test func gateBesideAProposalStillReachesTheFDE() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = try blocksRoot(in: tmp)

        let block = try #require(Blocks.load(root: root).first { $0.slug == "github-token" })
        #expect(
            !block.isProposal && NotebookFormat.unblockPrompt(block: block, agent: .claude).contains("fde-dev"),
            "a gate still reaches the forward-deployed engineer")
    }
}
