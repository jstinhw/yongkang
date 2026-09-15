import Foundation
import Testing

@testable import YongkangCore

@Suite struct AgentCommandTests {
    static let sid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    struct LineCase: CustomTestStringConvertible {
        var directory = "/a"
        let agent: AgentKind
        let prompt: String?
        var sessionID: UUID? = nil
        var brief = false
        var noCommit = false
        let expected: String
        var why: Comment? = nil

        var testDescription: String { "\(agent.rawValue): \(expected)" }
    }

    static let lineCases = [
        LineCase(directory: "/a b", agent: .claude, prompt: nil, expected: "cd '/a b' && exec claude"),
        LineCase(agent: .codex, prompt: "hi there", expected: "cd '/a' && exec codex 'hi there'"),
        LineCase(
            agent: .grok, prompt: "hi", sessionID: sid,
            expected: "cd '/a' && exec grok --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'hi'"),
        LineCase(
            agent: .agy, prompt: "hi", sessionID: sid,
            expected: "cd '/a' && exec agy --prompt-interactive 'hi'"),
        LineCase(
            agent: .claude, prompt: "hi", sessionID: sid,
            expected: "cd '/a' && exec claude --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'hi'"),
        LineCase(
            agent: .claude, prompt: nil, sessionID: sid,
            expected: "cd '/a' && exec claude --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        LineCase(
            agent: .claude, prompt: "lead", sessionID: sid, brief: true,
            expected: "cd '/a' && exec claude --brief --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'lead'",
            why: "engineering leads can notify the user without changing ordinary sessions"),
        LineCase(
            agent: .grok, prompt: "lead", sessionID: sid, noCommit: true,
            expected: "cd '/a' && exec grok --deny 'Bash(git commit:*)' --deny 'Bash(git push:*)' "
                + "--deny 'Bash(gh pr create:*)' --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'lead'",
            why: "a lead cannot commit — approving in Review is what commits"),
        LineCase(
            agent: .claude, prompt: "lead", noCommit: true,
            expected: "cd '/a' && exec claude --disallowedTools='Bash(git commit:*),Bash(git push:*),"
                + "Bash(gh pr create:*)' 'lead'",
            why: "the = form, or the variadic flag eats the prompt as a tool name"),
    ]

    /// What zsh actually passes to the agent for a given quoted argument.
    private func echo(_ quotedArgument: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf %s \(quotedArgument)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // The onboarding prompt reaches the agent as a shell argument, and it is full of
    // apostrophes, newlines, backticks and pipes. Round-trip it through a real shell.
    @Test func onboardingPromptSurvivesTheShell() throws {
        let typed = "It's a CLI that syncs \"stuff\"\nfast; `now`"
        let prompt = NotebookFormat.onboardingPrompt(description: typed)
        #expect(prompt.contains(typed), "what the user typed reaches the agent")
        #expect(prompt.contains("author's problem"), "the spec's apostrophes are what break quoting")
        #expect(prompt.contains("append one run record"), "setup sessions must leave a handoff")
        #expect(try echo(AgentCommand.quoted(prompt)) == prompt, "prompt mangled by the shell")
        #expect(try echo(AgentCommand.quoted("/a b'c")) == "/a b'c")
    }

    @Test(arguments: lineCases)
    func line(_ c: LineCase) {
        #expect(
            AgentCommand.line(
                directory: c.directory, agent: c.agent, prompt: c.prompt, sessionID: c.sessionID,
                brief: c.brief, noCommit: c.noCommit) == c.expected, c.why)
    }

    @Test func codexCarriesTheSessionIDInItsPrompt() {
        let codexLine = AgentCommand.line(directory: "/a", agent: .codex, prompt: "hi", sessionID: Self.sid)
        #expect(
            codexLine.hasPrefix("cd '/a' && exec codex 'hi"),
            "codex never understands --session-id, so the flag is never passed")
        #expect(
            codexLine.contains(AgentCommand.marker(Self.sid)),
            "the prompt carries the id instead — the only join from a row to its rollout")
        #expect(
            !AgentCommand.line(directory: "/a", agent: .claude, prompt: "hi", sessionID: Self.sid)
                .contains(AgentCommand.marker(Self.sid)),
            "claude has the flag and needs no marker in what the user reads")
    }

    @Test(arguments: [
        (AgentKind.claude, "review", "/product review"),
        (AgentKind.codex, "review", "$product review"),
        (AgentKind.claude, "describe", "/product describe"),
        (AgentKind.codex, "describe", "$product describe"),
        (AgentKind.grok, "describe", "/product describe"),
        (AgentKind.agy, "describe", "/product describe"),
    ])
    func skillInvocation(agent: AgentKind, arguments: String, expected: String) {
        #expect(agent.skillInvocation("product", arguments: arguments) == expected)
    }

    @Test func productPromptCarriesItsSessionID() {
        let productPrompt = NotebookFormat.productPrompt(arguments: "review", sessionID: Self.sid, agent: .claude)
        #expect(
            productPrompt.contains("/product review"),
            "Product needs its session id so Blocks can return to its transcript")
        #expect(
            productPrompt.contains("Session id: \(Self.sid.uuidString.lowercased())"),
            "Product needs its session id so Blocks can return to its transcript")
    }

    @Test func bundledSkillIsSelfContained() {
        let bundled = AgentKind.codex.skill(
            "product", arguments: "describe",
            instructions: "Only write notebook files.")
        #expect(
            bundled.contains("Only write notebook files."),
            "a packaged session must not depend on project or global skill discovery")
        #expect(
            bundled.contains("<arguments>\ndescribe\n</arguments>"),
            "a packaged session must not depend on project or global skill discovery")
        #expect(
            !bundled.contains("$product"),
            "a packaged session must not depend on project or global skill discovery")
    }

    // Only the app bundle carries skills, so this runs only when the tests run from inside one.
    @Test(.enabled(if: CommandLine.arguments[0].contains(".app/Contents/MacOS/")))
    func packagedAppCarriesTheProductSkill() {
        #expect(
            BundledSkills.load("product")?.contains("name: product") == true,
            "the packaged app must carry its Product skill")
    }
}
