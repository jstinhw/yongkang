import Foundation
import Testing

@testable import YongkangCore

/// The review page is drawn from what the agent wrote, so what it gets wrong has to come back
/// as a reason it can act on, and a spot has to land on the lines it names.
@Suite struct WorkReviewTests {

    @Test func aBrokenReviewSaysWhichField() throws {
        #expect(WorkReview.read("") == nil, "no section, no review")
        guard case .failure(let missing)? = WorkReview.read(#"{"summary": "Moved the feed."}"#) else {
            Issue.record("a review without a confidence was read")
            return
        }
        #expect(missing.reason == "confidence is missing.")
        guard case .failure(let none)? = WorkReview.read("Looks good to me.") else {
            Issue.record("prose was read as a review")
            return
        }
        #expect(none.reason == "There is no JSON object in it.")
    }

    @Test func aReviewArguesAgainstItself() throws {
        let clean = try #require(try WorkReview.read(#"{"summary": "s", "confidence": "high"}"#)?.get())
        #expect(!clean.cautions)
        let failed = try #require(
            try WorkReview.read(
                #"{"summary": "s", "confidence": "high", "checks": [{"claim": "c", "status": "failed"}]}"#)?.get())
        #expect(failed.cautions, "a failed check makes approving a decision against the agent's own report")
        let blocked = try #require(
            try WorkReview.read(
                #"{"summary": "s", "confidence": "high", "concerns": [{"title": "t", "blocks": true}]}"#)?
                .get())
        #expect(blocked.cautions)
    }

    @Test func aScreenIsAPageRunning() throws {
        let show = try #require(
            try WorkReview.read(
                #"{"summary": "s", "confidence": "high", "shows": [{"kind": "ui", "title": "Home", "after": "http://localhost:4321/", "serve_after": "npm run dev", "highlight": [".dl"]}]}"#
            )?.get().shows?.first)
        #expect(show.before == nil, "a new screen has nothing before it")
        #expect(show.serveAfter == "npm run dev")
        #expect(show.highlight == [".dl"])
        #expect(WorkReview.Show.page(show.after)?.port == 4321)
        #expect(WorkReview.Show.page("file:///etc/hosts") == nil, "only a web address is loaded")
        #expect(WorkReview.Show.page("docs/home.png") == nil)
    }

    /// Lines 3–4 of the new file: the removed line between them, and the one right before them,
    /// have no new number but belong to the change.
    @Test func aSpotTakesItsLinesAndTheRemovalsAmongThem() throws {
        let diff = [
            DiffLine(kind: .hunk, old: "", new: "", text: "@@ -1,4 +1,4 @@"),
            DiffLine(kind: .context, old: "1", new: "1", text: "a"),
            DiffLine(kind: .context, old: "2", new: "2", text: "b"),
            DiffLine(kind: .remove, old: "3", new: "", text: "old c"),
            DiffLine(kind: .add, old: "", new: "3", text: "c"),
            DiffLine(kind: .remove, old: "4", new: "", text: "old d"),
            DiffLine(kind: .add, old: "", new: "4", text: "d"),
            DiffLine(kind: .context, old: "5", new: "5", text: "e"),
        ]
        let spot = try #require(
            try WorkReview.read(
                #"{"summary": "s", "confidence": "low", "spots": [{"path": "f", "lines": [3, 4], "why": "w"}]}"#)?
                .get().spots?.first)
        #expect(spot.excerpt(of: diff).map(\.text) == ["old c", "c", "old d", "d"])
        let backwards = WorkReview.Spot(path: "f", lines: [4, 3], label: nil, why: "w")
        #expect(backwards.excerpt(of: diff).isEmpty, "lines that make no range show no code")
    }
}
