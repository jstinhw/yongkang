import Foundation

/// One member of the Engineering Lead's team: a name, the skill(s) that are its system
/// prompt, and a line on what it owns so the lead can route a task to it by name rather
/// than spawning a general subagent and telling it which skill to load.
///
/// Provider-neutral on purpose. The files live in `.notebook/team/`, not `.claude/agents/`
/// (which only Claude Code reads) — the lead routes by these files whether it is Claude
/// Code or Codex, and hands each skill to the specialist the same way a top-level session
/// gets one.
struct TeamMember: Identifiable, Equatable {
    var name: String
    var skills: [String]
    var owns: String
    var notes: String = ""

    var id: String { name }
}

enum Team {
    static let folder = "team"

    /// The roster shipped with the app. Written to `.notebook/team/` the first time a lead
    /// starts in a project that has a notebook; after that the files on disk are the truth.
    static let defaults: [TeamMember] = [
        // Two skills, in the order they run: Allen settles what a screen looks like and
        // the user approves it, then Allen builds it.
        TeamMember(
            name: "Allen", skills: ["designer", "frontend-dev"],
            owns: "Screens, components, styling, client state — anything the user sees, designed before it is built"),
        TeamMember(
            name: "Ben", skills: ["backend-dev"],
            owns: "Endpoints, schemas, migrations, jobs, server-side auth — anything behind an API"),
        TeamMember(
            name: "Chris", skills: ["sre-dev"],
            owns: "Deploying, hosting, CI, DNS, env vars, secrets, monitoring — anything needing an off-machine account"
        ),
        TeamMember(
            name: "David", skills: ["qa-dev"],
            owns: "Verifying finished work against its \u{201C}Done when\u{201D} list"),
        TeamMember(
            name: "Eric", skills: ["fde-dev"],
            owns: "Walking the user through a gate — started from Blocks, never dispatched by the lead"),
    ]

    static func directory(in notebookRoot: URL) -> URL {
        notebookRoot.appendingPathComponent(folder)
    }

    /// The roster the app shows and the lead routes by. Files on disk win; with no `team/`
    /// folder yet, the shipped defaults stand in so the roster is never empty. Shipped
    /// agents keep their canonical order; anything hand-added sorts after them by name.
    static func load(root: URL) -> [TeamMember] {
        let dir = directory(in: root)
        guard FileManager.default.fileExists(atPath: dir.path) else { return defaults }
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" }
        let order = defaults.map(\.name)
        return files.compactMap(member(at:)).sorted { a, b in
            let ai = order.firstIndex(of: a.name) ?? order.count
            let bi = order.firstIndex(of: b.name) ?? order.count
            return ai != bi ? ai < bi : a.name < b.name
        }
    }

    /// Who is running an agent with this label, and which of their skills it is running.
    /// The lead names every subagent `<task-id>-<skill>`, so the skill inside the label is
    /// what links a live agent back to a person on the roster — and the skill it matched is
    /// worth handing back, because a provider does not always say which one it spawned.
    static func running(_ label: String, in team: [TeamMember]) -> (member: TeamMember, skill: String)? {
        let haystack = Subagents.normalize(label)
        // Longest skill first, and roster order on a tie, so two agents given the same
        // skill resolve the same way every read rather than however the sort landed.
        return team.flatMap { member in member.skills.map { (member: member, skill: $0) } }
            .enumerated()
            .sorted { ($0.element.skill.count, -$0.offset) > ($1.element.skill.count, -$1.offset) }
            .first { haystack.contains(Subagents.normalize($0.element.skill)) }?.element
    }

    static func member(at url: URL) -> TeamMember? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fields = NotebookIndex.frontmatter(text)
        let skills = NotebookIndex.list(fields["skills"] ?? "")
        guard !skills.isEmpty else { return nil }
        let name =
            fields["name"].flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return TeamMember(
            name: name, skills: skills, owns: fields["owns"] ?? "",
            notes: NotebookIndex.body(text))
    }

    /// Writes the shipped roster to `.notebook/team/` once. A folder that already exists —
    /// even trimmed to a subset — is the user's, and is left alone.
    static func seedIfAbsent(root: URL) {
        let dir = directory(in: root)
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        for member in defaults { try? write(member, root: root) }
    }

    static func file(for name: String, root: URL) -> URL {
        directory(in: root).appendingPathComponent("\(NotebookFormat.slug(name)).md")
    }

    static func write(_ member: TeamMember, root: URL) throws {
        try FileManager.default.createDirectory(at: directory(in: root), withIntermediateDirectories: true)
        let skills = "[" + member.skills.joined(separator: ", ") + "]"
        let front = "---\nname: \(member.name)\nskills: \(skills)\nowns: \(yaml(member.owns))\n---"
        let body =
            member.notes.isEmpty
            ? "The skill\(member.skills.count == 1 ? " is" : "s are") the job — put standing notes for this agent here.\n"
            : member.notes + "\n"
        try (front + "\n\n" + body).write(
            to: file(for: member.name, root: root),
            atomically: true, encoding: .utf8)
    }

    private static func yaml(_ value: String) -> String {
        "\""
            + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
