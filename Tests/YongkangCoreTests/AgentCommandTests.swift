import Foundation
import Testing

@testable import YongkangCore

@Suite struct AgentCommandTests {
    static let sid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    /// Codex's update offer, which would stop every session before its prompt, turned off.
    static let noUpdate = "-c check_for_update_on_startup=false"

    struct LineCase: CustomTestStringConvertible {
        var directory = "/a"
        let agent: AgentKind
        let prompt: String?
        var sessionID: UUID? = nil
        var noCommit = false
        var reading: [String] = []
        let expected: String
        var why: Comment? = nil

        var testDescription: String { "\(agent.rawValue): \(expected)" }
    }

    static let lineCases = [
        LineCase(directory: "/a b", agent: .claude, prompt: nil, expected: "cd '/a b' && exec claude"),
        LineCase(agent: .codex, prompt: "hi there", expected: "cd '/a' && exec codex \(Self.noUpdate) 'hi there'"),
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
            agent: .grok, prompt: "work", sessionID: sid, noCommit: true,
            expected: "cd '/a' && exec grok --deny 'Bash(git commit:*)' --deny 'Bash(git push:*)' "
                + "--deny 'Bash(gh pr create:*)' --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'work'",
            why: "an assigned session cannot commit — approving in Review is what commits"),
        LineCase(
            agent: .claude, prompt: "work", noCommit: true,
            expected: "cd '/a' && exec claude --disallowedTools='Bash(git commit:*),Bash(git push:*),"
                + "Bash(gh pr create:*)' 'work'",
            why: "the = form, or the variadic flag eats the prompt as a tool name"),
        LineCase(
            agent: .claude, prompt: "hi", sessionID: sid, reading: ["/b c"],
            expected: "cd '/a' && exec claude --add-dir '/b c' --session-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee 'hi'",
            why: "--add-dir is variadic, so it goes ahead of a flag that ends it — never next to the prompt"),
        LineCase(
            agent: .codex, prompt: "hi", reading: ["/b"],
            expected: "cd '/a' && exec codex \(Self.noUpdate) --add-dir '/b' 'hi'"),
        LineCase(
            agent: .agy, prompt: "hi", reading: ["/b", "/c"],
            expected: "cd '/a' && exec agy --add-dir '/b' --add-dir '/c' --prompt-interactive 'hi'"),
        LineCase(
            agent: .grok, prompt: "hi", reading: ["/b"], expected: "cd '/a' && exec grok 'hi'",
            why: "grok takes no folder beside its own, so it is handed none"),
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
        let session = UUID()
        let prompt = NotebookFormat.onboardingPrompt(description: typed, sessionID: session)
        #expect(prompt.contains(typed), "what the user typed reaches the agent")
        #expect(
            prompt.contains("stage: ready") && prompt.contains("session: \(session.uuidString.lowercased())"),
            "the plan is drafted as a ready proposal that Create project brings back to this session")
        #expect(prompt.contains("author's problem"), "the spec's apostrophes are what break quoting")
        #expect(prompt.contains("append one run record"), "setup sessions must leave a handoff")
        #expect(
            prompt.contains("as your last write, set the draft's `status: done`"),
            "the draft turning done is what ends the session, so nothing may be written after it")
        #expect(prompt.contains("design nothing"), "setup plans design as tasks; the page it shows is the plan")
        #expect(try echo(AgentCommand.quoted(prompt)) == prompt, "prompt mangled by the shell")
        #expect(try echo(AgentCommand.quoted("/a b'c")) == "/a b'c")
    }

    @Test func aFolderWithCodeIsReadIntoARoadmapOnly() throws {
        let prompt = NotebookFormat.onboardingPrompt(description: nil, sessionID: Self.sid)
        #expect(prompt.contains("read the whole project"), "the code says what the project is for")
        #expect(!prompt.contains("one question at a time"), "nothing is asked")
        #expect(!prompt.contains("blocks/plan.md"), "an import has no plan to approve: Product plans from the roadmap")
        #expect(
            prompt.contains("As your last write, one roadmap entry"),
            "the roadmap appearing is what ends the session, so it comes after the run record")
        #expect(prompt.contains("One run record"), "an import leaves a handoff like any setup")
        #expect(prompt.contains("author's problem"), "the spec goes in verbatim")
        #expect(try echo(AgentCommand.quoted(prompt)) == prompt, "prompt mangled by the shell")
    }

    @Test(arguments: lineCases)
    func line(_ c: LineCase) {
        #expect(
            AgentCommand.line(
                directory: c.directory, agent: c.agent, prompt: c.prompt, sessionID: c.sessionID,
                noCommit: c.noCommit, reading: c.reading) == c.expected, c.why)
    }

    @Test func codexCarriesTheSessionIDInItsPrompt() {
        let codexLine = AgentCommand.line(directory: "/a", agent: .codex, prompt: "hi", sessionID: Self.sid)
        #expect(
            codexLine.hasPrefix("cd '/a' && exec codex \(Self.noUpdate) 'hi"),
            "codex never understands --session-id, so the flag is never passed")
        #expect(
            codexLine.contains(CodexProvider.marker(Self.sid)),
            "the prompt carries the id instead — the only join from a row to its rollout")
        #expect(
            !AgentCommand.line(directory: "/a", agent: .claude, prompt: "hi", sessionID: Self.sid)
                .contains(CodexProvider.marker(Self.sid)),
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

    @Test func aWorkPromptSaysWhatElseItMayReadAndNotChange() {
        let task = NotebookCard(
            id: "wire-auth", url: URL(fileURLWithPath: "/a/.notebook/tasks/wire-auth.md"), kind: .task,
            title: "Wire auth", status: "todo", project: nil, dependsOn: [])
        #expect(!NotebookFormat.workPrompt(tasks: [task], sessionID: Self.sid).contains("You may also read"))
        let prompt = NotebookFormat.workPrompt(tasks: [task], sessionID: Self.sid, reading: ["/b"])
        #expect(prompt.contains("You may also read `/b`") && prompt.contains("Change nothing there"))
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

    @Test func setupAndProductShowThePlanAsTheSameGraph() {
        let setup = NotebookFormat.onboardingPrompt(description: "a site", sessionID: Self.sid)
        let product = NotebookFormat.productPrompt(arguments: "describe", sessionID: Self.sid, agent: .codex)
        for prompt in [setup, product] {
            #expect(prompt.contains("`flowchart LR`"), "the dependencies are drawn, not listed")
        }
    }

    @Test func everyPageGoesOnTheSessionsTabNotABrowser() {
        let page = ".notebook/pages/\(Self.sid.uuidString.lowercased()).html"
        let task = NotebookCard(
            id: "wire-auth", url: URL(fileURLWithPath: "/p/.notebook/tasks/wire-auth.md"), kind: .task,
            title: "Wire auth", status: "todo", project: nil, dependsOn: [])
        for prompt in [
            NotebookFormat.onboardingPrompt(description: "a site", sessionID: Self.sid),
            NotebookFormat.productPrompt(arguments: "describe", sessionID: Self.sid, agent: .codex),
            NotebookFormat.workPrompt(tasks: [task], sessionID: Self.sid),
        ] {
            #expect(prompt.contains(page), "the app shows the page it knows the path of")
            #expect(!prompt.contains("temp directory"), "a page the agent opens itself lands in a browser")
        }
        #expect(
            NotebookFormat.page(of: Self.sid, in: URL(fileURLWithPath: "/p/.notebook")).path == "/p/" + page,
            "the tab reads the file the prompt named")
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

    /// What the agent picker sorts on. The stand-in shell ignores the script it is handed and
    /// prints what a login shell with a chatty rc file and two of the CLIs would.
    @Test func installedReadsOnlyTheMarkedLines() async {
        let shell = [
            "/bin/sh", "-c", "printf 'codex is great\\nyongkang-found:codex\\nyongkang-found:agy\\n'", "sh",
        ]
        #expect(await AgentKind.installed(shell: shell) == [.codex, .agy])
        #expect(await AgentKind.installed(shell: ["/nonexistent/shell", "-c"]) == nil, "no shell is not no CLIs")
    }
}
