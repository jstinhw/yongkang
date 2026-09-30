import Foundation
import Testing

@testable import YongkangCore

/// Discovery reads `$HOME/.claude/skills`, `$HOME/.agents/skills` and the packaged skills as
/// well as the project, read-only. The checks below only look for names they install
/// themselves, so whatever the developer has installed at home cannot change the result.
@Suite struct SkillsTests {
    private func writeSkill(_ folder: URL, _ name: String, described: String) throws {
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(name),
            withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: \(described)\n---\n\nDo the thing."
            .write(to: folder.appendingPathComponent("\(name)/SKILL.md"), atomically: true, encoding: .utf8)
    }

    // The skill behind a team member, as its page reads it: the block-list `allowed-tools`
    // the flat frontmatter reader cannot see, and a body that stops at the frontmatter.
    @Test func skillPageReadsItsFrontmatter() {
        let skillText = """
            ---
            name: frontend-dev
            description: Build the user-facing half of one Yongkang task.
            allowed-tools:
              - Read
              - Write
            model: opus
            ---

            You are the frontend engineer on one task:

            - Read the task file first.
            """
        let skill = SkillDoc.parse(skillText, named: "whatever")
        #expect(skill.name == "frontend-dev", "the file names the skill, not the caller")
        #expect(skill.summary.hasPrefix("Build the user-facing half"))
        #expect(skill.tools == ["Read", "Write"], "a block list of tools is read, and stops before the next field")
        #expect(
            skill.body.hasPrefix("You are the frontend engineer")
                && skill.body.contains("- Read the task file first."),
            "a bullet in the body is instructions, never another tool")
    }

    @Test func skillWithoutFrontmatterOrWithAnInlineToolList() {
        #expect(
            SkillDoc.parse("no frontmatter here", named: "qa-dev")
                == SkillDoc(name: "qa-dev", summary: "", tools: [], body: "no frontmatter here", url: nil),
            "a skill file without frontmatter still reads as its instructions")
        #expect(
            SkillDoc.parse("---\nallowed-tools: [Read, Bash]\n---\nGo.", named: "x").tools == ["Read", "Bash"],
            "an inline tool list reads the same way")
    }

    // Where a new agent's skills come from: the folders both providers read, project
    // before home before the packaged copies, and a git repo installed into the first.
    @Test func discoveryCoversBothProvidersFolders() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let projectSkills = tmp.appendingPathComponent(".claude/skills")
        try writeSkill(projectSkills, "migrations-dev", described: "Owns schema migrations.")
        try writeSkill(tmp.appendingPathComponent(".agents/skills"), "docs-dev", described: "Writes the docs.")

        let catalog = Skills.available(project: tmp)
        #expect(
            catalog.contains { $0.name == "migrations-dev" && $0.summary == "Owns schema migrations." },
            "a skill installed in the project is one the roster can hand out")
        #expect(
            catalog.contains { $0.name == "docs-dev" },
            "and so is one only Codex's folder holds — the form offers both providers' skills")
        #expect(
            Skills.url("migrations-dev", project: tmp)?.path
                == projectSkills.appendingPathComponent("migrations-dev/SKILL.md").path,
            "the project's own copy is the file its agents would actually load")
        #expect(Skills.url("nothing-installed", project: tmp) == nil)
        #expect(
            catalog.map(\.name) == catalog.map(\.name).sorted() && Set(catalog.map(\.name)).count == catalog.count,
            "one row per name, in the order the picker draws them")
        #expect(
            SkillDoc.load("migrations-dev", project: tmp).summary == "Owns schema migrations.",
            "a member's page reads the installed skill, not just a packaged one")
    }

    // The Skills page: shared is every CLI's home folders; one CLI sees only its own folders,
    // and a project copy hides the shared one it shadows.
    @Test func eachCLIListsOnlyTheFoldersItReads() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (home, project) = (tmp.appendingPathComponent("home"), tmp.appendingPathComponent("project"))
        try writeSkill(home.appendingPathComponent(".claude/skills"), "review", described: "Shared review.")
        try writeSkill(home.appendingPathComponent(".agents/skills"), "guidelines", described: "Codex's.")
        try writeSkill(project.appendingPathComponent(".claude/skills"), "review", described: "This project's.")

        #expect(
            Skills.shared(home: home).map(\.name) == ["guidelines", "review"],
            "every CLI's home folders, one row a name")

        let claude = Skills.loaded(by: .claude, project: project, home: home)
        #expect(claude.project.map(\.summary) == ["This project's."])
        #expect(claude.shared.isEmpty, "the shared review is shadowed, and Claude Code never reads ~/.agents")

        let codex = Skills.loaded(by: .codex, project: project, home: home)
        #expect(codex.project.isEmpty, "Codex does not read .claude/skills")
        #expect(codex.shared.map(\.name) == ["guidelines"])
    }

    // A SKILL.md that calls itself something else is still only reachable at its folder.
    @Test func folderNamesTheSkillNotItsFrontmatter() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let projectSkills = tmp.appendingPathComponent(".claude/skills")
        try writeSkill(projectSkills, "migrations-dev", described: "Owns schema migrations.")
        try writeSkill(projectSkills, "_alias-dev", described: "Claims another name.")
        try "---\nname: migrations-dev\ndescription: Claims another name.\n---\n\nGo."
            .write(to: projectSkills.appendingPathComponent("_alias-dev/SKILL.md"), atomically: true, encoding: .utf8)

        let aliased = Skills.available(project: tmp)
        #expect(
            aliased.contains { $0.name == "_alias-dev" }, "the folder names a skill in the picker, not its frontmatter")
        #expect(
            Set(aliased.map(\.name)).count == aliased.count,
            "so two skills can never collide into one row the lead cannot resolve")
    }

    // A repo is sometimes one skill, sometimes a folder of them, sometimes keeps them
    // under `skills/` — all three are found, and `.git` is never mistaken for one.
    @Test func skillFoldersInACheckout() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let checkout = tmp.appendingPathComponent("checkout")
        try writeSkill(checkout.appendingPathComponent("skills"), "deep-dev", described: "Nested.")
        try FileManager.default.createDirectory(
            at: checkout.appendingPathComponent(".git/skills/hidden-dev"),
            withIntermediateDirectories: true)
        try "---\nname: hidden\n---\n"
            .write(
                to: checkout.appendingPathComponent(".git/skills/hidden-dev/SKILL.md"), atomically: true,
                encoding: .utf8)
        #expect(
            Skills.skillFolders(in: checkout).map(\.lastPathComponent) == ["deep-dev"],
            "a skill under skills/ is found; anything inside a dot folder is not")

        try "---\nname: root-dev\ndescription: At the repo root.\n---\n\nDo the thing."
            .write(to: checkout.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(
            Skills.skillFolders(in: checkout).map(\.lastPathComponent) == [checkout.lastPathComponent],
            "a repo that is itself one skill stops the search at its root")
        #expect(
            Skills.installName(of: checkout) == "root-dev",
            "and installs under the name its own frontmatter claims, not the repo's")
        #expect(Skills.repositoryName("git@github.com:owner/Team-Skills.git") == "team-skills")
    }

    // The remote is handed to `git clone` as an argument, never through a shell: this
    // is about a "URL" that is really a git flag or a path to somewhere else on disk.
    @Test(arguments: [
        ("https://github.com/owner/skills.git", true),
        ("git@github.com:owner/skills.git", true),
        ("--upload-pack=/bin/sh", false),
        ("~/Documents/skills", false),
        ("https://host/a b", false),
    ])
    func onlyARealRemoteIsCloned(_ remote: String, _ isRemote: Bool) {
        #expect(Skills.isRemote(remote) == isRemote)
    }

    @Test func aFlagPosingAsARemoteIsRefused() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(throws: (any Error).self, "a remote that is not one is refused before git is started") {
            _ = try Skills.install(git: "--upload-pack=x", into: tmp)
        }
    }

    // The clone itself, only when asked: `YK_NETWORK_TESTS=<git url> swift test --filter
    // SkillsTests`. The variable is both the switch and the remote to clone (it replaces
    // the self-test's SELFTEST_REMOTE). Off by default because a check that needs the
    // network fails for reasons that have nothing to do with this app.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YK_NETWORK_TESTS"] != nil))
    func installsARealRemote() throws {
        let remote = try #require(ProcessInfo.processInfo.environment["YK_NETWORK_TESTS"])
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let codexSkills = tmp.appendingPathComponent(".agents/skills")

        let installed = try Skills.install(git: remote, into: tmp)
        #expect(!installed.isEmpty, "a skills repo installs at least one skill")
        for name in installed {
            #expect(Skills.url(name, project: tmp) != nil, "\(name) is loadable after install")
            let link = try? FileManager.default.destinationOfSymbolicLink(
                atPath: codexSkills.appendingPathComponent(name).path)
            #expect(link != nil, "and Codex gets the same file through .agents/skills/")
        }
        #expect(Set(Skills.available(project: tmp).map(\.name)).isSuperset(of: installed))
    }

    // A SKILL.md's `name:` is third-party text. What it installs as is slugged, and the
    // picker lists it under its folder, so `../` in the name reaches no path.
    @Test func dotDotSkillNameIsSlugged() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let checkout = tmp.appendingPathComponent("checkout")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try "---\nname: ../../escape\n---\n\nGo."
            .write(to: checkout.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(Skills.installName(of: checkout) == "escape", "an install name is a slug, never a path")

        let projectSkills = tmp.appendingPathComponent(".claude/skills")
        try writeSkill(projectSkills, "honest-dev", described: "Claims a path.")
        try "---\nname: ../../escape\n---\n\nGo."
            .write(to: projectSkills.appendingPathComponent("honest-dev/SKILL.md"), atomically: true, encoding: .utf8)
        #expect(
            Skills.available(project: tmp).contains { $0.name == "honest-dev" },
            "the picker lists it under its folder")
        #expect(!Skills.available(project: tmp).contains { $0.name.contains("..") })
    }

    // A team file's `skills:` are agent-written names, and a member's page loads each one
    // through `Skills.url`. A name that climbs out with `../` should resolve to nothing.
    @Test func dotDotSkillNameDoesNotEscapeTheSkillRoots() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try writeSkill(tmp.appendingPathComponent(".claude/skills"), "migrations-dev", described: "Real.")
        try writeSkill(tmp, "outside", described: "Not an installed skill.")

        let team = Team.directory(in: NotebookFormat.root(in: tmp))
        try FileManager.default.createDirectory(at: team, withIntermediateDirectories: true)
        let file = team.appendingPathComponent("climber.md")
        try "---\nname: Climber\nskills: [../../outside]\nowns: Nothing\n---\n"
            .write(to: file, atomically: true, encoding: .utf8)
        let member = try #require(Team.member(at: file))
        #expect(member.skills == ["../../outside"], "the team file's skill name is read back verbatim")

        withKnownIssue(
            "Skills.url appends the name to each root unchecked, so `../../outside` reads <project>/outside/SKILL.md"
        ) {
            #expect(Skills.url("../../outside", project: tmp) == nil)
            #expect(
                SkillDoc.load(member.skills[0], project: tmp).url == nil,
                "a member's page must not load a SKILL.md from outside the skill folders")
        }
    }
}
