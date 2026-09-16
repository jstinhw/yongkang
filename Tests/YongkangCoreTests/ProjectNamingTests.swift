import Foundation
import Testing

@testable import YongkangCore

/// A described project's folder is named by the agent, in a one-shot run of its CLI. What has to
/// hold is reading a name out of whatever the CLI prints, and saying why when it prints none.
@Suite struct ProjectNamingTests {
    @Test(arguments: [
        ("weather-cli", "weather-cli", "the reply the prompt asks for"),
        ("Loading config…\n`Photo Renamer`\n\n", "photo-renamer", "the last line, quoted or not"),
        (
            "Sure! A good name would be the-photo-renamer-for-my-trip", "sure-a-good-name-would",
            "a sentence is cut to five words"
        ),
    ])
    func readsTheNameOffTheLastLine(answer: String, name: String, why: String) {
        #expect(ProjectNaming.name(from: answer) == name, Comment(rawValue: why))
    }

    @Test func printingNothingIsNoName() {
        #expect(ProjectNaming.name(from: "") == nil)
        #expect(ProjectNaming.name(from: "  \n…\n") == nil, "nothing a folder can be called")
    }

    /// Every CLI answers the prompt, quoted, as the last word, so a description with quotes and
    /// newlines reaches it whole.
    @Test(arguments: AgentKind.allCases)
    func everyProviderAsksWithTheQuotedPrompt(agent: AgentKind) {
        let prompt = "It's a \"CLI\"\nthat renames photos"
        #expect(agent.provider.ask(prompt: prompt).last == AgentCommand.quoted(prompt))
    }

    @Test func asksThroughTheShellAndReturnsTheName() async throws {
        // Stands in for the login shell: prints a banner, then the name, and ignores the line.
        let shell = ["/bin/sh", "-c", "printf 'welcome back\\nphoto-renamer\\n'", "sh"]
        let name = try await ProjectNaming.ask(.claude, description: "renames photos", shell: shell)
        #expect(name == "photo-renamer")
    }

    @Test func aFailedRunSaysWhatTheCLISaid() async throws {
        let shell = ["/bin/sh", "-c", "echo 'Not logged in.' >&2; exit 1", "sh"]
        do {
            _ = try await ProjectNaming.ask(.codex, description: "renames photos", shell: shell)
            Issue.record("a failed run must not produce a name")
        } catch let failure as ProjectNaming.Failure {
            #expect(failure.localizedDescription == "Codex could not name the project: Not logged in")
        }
    }
}
