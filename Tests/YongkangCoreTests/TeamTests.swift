import Foundation
import Testing

@testable import YongkangCore

@Suite struct TeamTests {
    private func routing(_ members: [TeamMember]) -> [[String]] {
        members.map { [$0.name, $0.skills.joined(separator: ","), $0.owns] }
    }

    private let mobileDev = TeamMember(
        name: "mobile-dev", skills: ["frontend-dev"],
        owns: "Native app screens", notes: "Ships the iOS target.")

    // The team the lead routes by: shipped defaults, then `.notebook/team/` files win.
    @Test func shippedRosterThenFilesWin() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = NotebookFormat.root(in: tmp)

        #expect(Team.load(root: root) == Team.defaults, "no team/ folder falls back to the shipped roster")
        Team.seedIfAbsent(root: root)
        #expect(
            routing(Team.load(root: root)) == routing(Team.defaults),
            "seeding writes the shipped roster verbatim")
        Team.seedIfAbsent(root: root)
        #expect(Team.load(root: root).count == Team.defaults.count, "seeding a populated folder is a no-op")
        try Team.write(mobileDev, root: root)
        let roster = Team.load(root: root)
        #expect(
            roster.contains {
                $0.name == "mobile-dev" && $0.skills == ["frontend-dev"]
                    && $0.notes == "Ships the iOS target."
            },
            "a hand-written agent file joins the roster, body and all")
        #expect(roster.count == Team.defaults.count + 1)
    }

    // Who a running agent is: the lead names it `<task-id>-<skill>`, and the skill in
    // that name is what puts a person's face on every screen that shows the agent.
    private func running(_ label: String, _ type: String, in team: [TeamMember] = Team.defaults) -> SubagentStatus {
        SubagentStatus(
            id: label, description: label, agentType: type, running: true,
            transcriptURL: URL(fileURLWithPath: "/dev/null")
        ).named(in: team)
    }

    struct Identity: Sendable, CustomTestStringConvertible {
        let label: String
        let type: String
        let displayName: String
        let why: String?
        var testDescription: String { label }
    }

    @Test(arguments: [
        Identity(label: "edit-todo-frontend-dev", type: "frontend-dev", displayName: "Allen", why: nil),
        Identity(label: "deploy-to-vercel-sre-dev", type: "sre-dev", displayName: "Chris", why: nil),
        Identity(
            label: "qa-dev: edit-todo", type: "qa-dev", displayName: "David",
            why: "a label the lead punctuated its own way still names the right agent"),
        Identity(
            label: "Compact conversation", type: "general-purpose", displayName: "general-purpose",
            why: "an agent no one on the team owns keeps its own name"),
    ])
    func runningAgentIsNamedBySkill(_ row: Identity) {
        #expect(running(row.label, row.type).displayName == row.displayName, row.why.map(Comment.init(rawValue:)))
    }

    @Test func shippedAgentOutranksAHandAddedOneWithTheSameSkill() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = NotebookFormat.root(in: tmp)
        Team.seedIfAbsent(root: root)
        try Team.write(mobileDev, root: root)
        let roster = Team.load(root: root)

        #expect(
            running("edit-todo-frontend-dev", "frontend-dev").named(in: roster).member == "Allen",
            "a hand-added agent sharing a skill never outranks the one shipped with it")
    }

    // Codex nicknames a thread it spawns; the skill in the label is what the run is
    // filed under, so the tile has a colour and the ledger row groups under a person.
    @Test func codexNicknameNeverSurvivesAsARole() {
        let nicknamed = running("render_task_groups_frontend_dev", "Dewey")
        #expect(
            nicknamed.displayName == "Allen" && nicknamed.agentType == "frontend-dev",
            "a provider's nickname never survives as an agent's role")
    }

    // `name:` in a team file is agent-written. It is read back verbatim as a label, but
    // the file a member is saved to is slugged, so `../` in a name cannot leave team/.
    @Test func dotDotNameStaysInsideTheTeamFolder() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = NotebookFormat.root(in: tmp)
        let team = Team.directory(in: root)
        try FileManager.default.createDirectory(at: team, withIntermediateDirectories: true)
        try "---\nname: ../../escape\nskills: [qa-dev]\nowns: Nothing\n---\n"
            .write(to: team.appendingPathComponent("sneaky.md"), atomically: true, encoding: .utf8)

        let loaded = try #require(Team.load(root: root).first)
        #expect(loaded.name == "../../escape", "the name is a label, read back as written")
        #expect(
            Team.file(for: loaded.name, root: root).path == team.appendingPathComponent("escape.md").path,
            "the file it saves to is slugged into team/")
        try Team.write(loaded, root: root)
        #expect(FileManager.default.fileExists(atPath: team.appendingPathComponent("escape.md").path))
        #expect(
            !FileManager.default.fileExists(atPath: tmp.appendingPathComponent("escape.md").path)
                && !FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.md").path),
            "nothing is written outside team/")
    }
}
