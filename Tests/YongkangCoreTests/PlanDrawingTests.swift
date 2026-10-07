import Foundation
import Testing

@testable import YongkangCore

/// The plan setup and Product hand over, laid out for its page. What the user reads in the
/// first seconds is where a card sits and what it is marked, so those are what is checked.
@Suite struct PlanDrawingTests {
    private func drawing(_ json: String) throws -> PlanDrawing {
        PlanDrawing(try Plan.decode(Data(json.utf8)))
    }

    @Test func theDownloadPlanReadsInBuildOrder() throws {
        let plan = try drawing(fixture("notebook/plan-download.json"))
        let node = Dictionary(uniqueKeysWithValues: plan.nodes.map { ($0.id, $0) })
        let design = try #require(node["download-design"])
        let repoSwitch = try #require(node["release-repo-switch"])
        let buttons = try #require(node["download-buttons"])
        let live = try #require(node["download-live-check"])
        let release = try #require(node["first-public-release"])

        #expect(node["waitlist-form-states"]!.x == node["release-info"]!.x)
        #expect(node["release-info"]!.x < design.x && design.x == repoSwitch.x)
        #expect(repoSwitch.x < buttons.x && buttons.x < live.x, "a task sits right of what it waits on")
        #expect(release.x == buttons.x, "what the plan builds on sits just left of what waits on it")
        #expect(node["vercel-deploy"]!.x == repoSwitch.x, "what the plan builds on sits just left of what waits on it")
        let chain: [Int] = [node["release-info"]!.y, repoSwitch.y, buttons.y, live.y]
        #expect(Set(chain).count == 1, "a chain runs straight")
        #expect(node["waitlist-form-states"]!.y == design.y, "what the plan builds on sits level with its task")

        let band = try #require(plan.bands.first)
        #expect(plan.bands.count == 1 && band.title == "open-source-download")
        for outside in [release, node["vercel-deploy"]!] {
            #expect(outside.y >= band.y + band.height, "a band holds only its own project's tasks")
        }
        #expect(band.x < design.x && band.x + band.width > live.x + plan.nodeWidth)

        #expect(plan.nodes.filter(\.ready).map(\.id) == ["download-design", "release-repo-switch"])
        #expect(plan.nodes.filter(\.you).map(\.id) == ["download-design", "download-live-check"])
        #expect(plan.nodes.filter(\.design).map(\.id) == ["download-design"])
        #expect(release.kind == .pending && node["release-info"]?.kind == .built)
        #expect(plan.edges.filter(\.dashed).map(\.from) == ["first-public-release"])
        #expect(plan.edges.count == 7)
        expectNoOverlap(plan)
    }

    /// Three arrows into one card arrive spread down its edge, top source highest.
    @Test func arrowsIntoOneCardDoNotShareAPoint() throws {
        let plan = try drawing(fixture("notebook/plan-download.json"))
        let into = plan.edges.filter { $0.to == "download-buttons" }
        #expect(into.map(\.from) == ["download-design", "release-repo-switch", "vercel-deploy"].sorted())
        let arrivals = into.sorted { $0.y1 < $1.y1 }.map(\.y2)
        #expect(arrivals == arrivals.sorted() && Set(arrivals).count == 3)
    }

    /// An agent's plan can loop, name what does not exist, or repeat itself. It still draws,
    /// with every card in a place of its own.
    @Test func aPlanWrittenBadlyStillDraws() throws {
        let plan = try drawing(
            """
            {"title": "Loop", "tasks": [
              {"id": "a", "title": "A", "depends_on": ["b", "ghost", "a"]},
              {"id": "b", "title": "B", "depends_on": ["a"]},
              {"id": "a", "title": "A again"}
            ]}
            """)
        #expect(plan.nodes.map(\.id) == ["a", "b"])
        #expect(!plan.edges.contains { $0.from == "ghost" || $0.from == $0.to })
        expectNoOverlap(plan)
    }

    @Test func aPlanWithoutTasksIsNotAPlan() {
        #expect(throws: DecodingError.self) { try drawing(#"{"title": "Nothing"}"#) }
    }

    /// The Page tab shows whichever of the plan and the page the session wrote last.
    @Test func theTabShowsWhatWasWrittenLast() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let session = UUID()
        #expect(NotebookFormat.drawnPage(of: session, in: tmp) == nil)
        let page = NotebookFormat.page(of: session, in: tmp)
        let plan = NotebookFormat.plan(of: session, in: tmp)
        try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "<p>Report</p>".write(to: page, atomically: true, encoding: .utf8)
        try "{}".write(to: plan, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: page.path)
        #expect(NotebookFormat.drawnPage(of: session, in: tmp)?.url == plan)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: plan.path)
        #expect(NotebookFormat.drawnPage(of: session, in: tmp)?.url == page)
    }

    private func expectNoOverlap(_ plan: PlanDrawing) {
        for (index, a) in plan.nodes.enumerated() {
            for b in plan.nodes.dropFirst(index + 1) {
                let apart =
                    a.x + plan.nodeWidth <= b.x || b.x + plan.nodeWidth <= a.x
                    || a.y + plan.nodeHeight <= b.y || b.y + plan.nodeHeight <= a.y
                #expect(apart, "\(a.id) and \(b.id) overlap")
            }
        }
    }
}
