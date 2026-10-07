import Foundation
import YongkangUI

extension DesignShots {
    /// The plan page, as the page itself: offscreen a web view photographs as an empty frame,
    /// so this one screen is written out as `plan.html`, drawn from the plan the tests read.
    /// Open it in a browser to compare two runs.
    @MainActor static func writePlanPage(into directory: URL) {
        let plan = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Shots
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Tests/YongkangCoreTests/Fixtures/notebook/plan-download.json")
        do {
            try PlanPage.html(contentsOf: plan)
                .write(to: directory.appendingPathComponent("plan.html"), atomically: true, encoding: .utf8)
        } catch {
            print("could not write plan.html: \(error.localizedDescription)")
        }
    }
}
