import Foundation
import Testing

@testable import YongkangUI

/// The page a plan is drawn on reads what an agent wrote, so what it wrote must stay text, and
/// a plan written wrong must say what to fix rather than draw an empty pane.
@Suite struct PlanPageTests {
    private func page(_ json: String) throws -> String {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = tmp.appendingPathComponent("plan.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return PlanPage.html(contentsOf: url)
    }

    @Test func theFixtureDrawsInTheAppsColours() throws {
        let html = try page(fixture("notebook/plan-download.json"))
        #expect(html.contains("--amber: \(Theme.amber.css);") && Theme.amber.css == "#F3B455")
        #expect(html.contains(#""id":"download-design""#))
        #expect(!html.contains("cdn."), "the page loads nothing from a server")
    }

    @Test func aTitleCannotCloseTheScriptItSitsIn() throws {
        let html = try page(
            #"{"title": "</script><script>alert(1)</script>", "tasks": [{"id": "a", "title": "<!-- b"}]}"#)
        #expect(!html.contains("<script>alert"))
        #expect(!html.contains("<!-- b"))
        #expect(html.contains(#"</script>"#), "still there, as text the page parses back")
    }

    @Test func aPlanWrittenWrongSaysWhichFieldToFix() throws {
        let html = try page(#"{"title": "Half", "tasks": [{"id": "a"}]}"#)
        #expect(html.contains("This plan could not be read: tasks.0.title is missing."))
        #expect(try page("{").contains("This plan could not be read"))
    }
}
