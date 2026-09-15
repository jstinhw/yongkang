import Foundation

/// Where a skill comes from. A team member's `skills:` are names; the provider running
/// the agent resolves a name by looking in its own folders, so the app looks in exactly
/// those — otherwise the roster offers skills no agent can load, or hides ones it can.
///
/// Installing a remote skill is the same idea in reverse: drop the folder where the
/// provider is already looking (`.claude/skills/` for Claude Code, `.agents/skills/` for
/// Codex, linked to the same file so the two cannot drift) and it is available to both.
package enum Skills {
    /// The two folder names each provider reads, relative to a project or to `$HOME`.
    static let folders = [".claude/skills", ".agents/skills"]

    /// Every root holding `<name>/SKILL.md`, project first: a project's own copy of a
    /// skill is the one its agents will actually run, and the packaged copies last
    /// because they are the fallback the app ships rather than anything the user chose.
    static func roots(project: URL?) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let scoped = project.map { root in folders.map { root.appendingPathComponent($0) } } ?? []
        return scoped + folders.map { home.appendingPathComponent($0) } + [BundledSkills.root].compactMap { $0 }
    }

    /// The skill folders directly inside one root. `fileExists` resolves symlinks, so a
    /// `.agents/skills/` full of links to `.claude/skills/` reads as the same skills.
    static func folders(in root: URL) -> [URL] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The file behind a skill name, or nil if nothing installed answers to it.
    static func url(_ name: String, project: URL?) -> URL? {
        roots(project: project)
            .map { $0.appendingPathComponent("\(name)/SKILL.md") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Every skill this project could give an agent, one entry per name — the first root
    /// that answers to a name wins, so a project copy shadows the packaged one.
    package static func available(project: URL?) -> [SkillDoc] {
        var seen: Set<String> = []
        return roots(project: project)
            .flatMap(folders(in:))
            .filter { seen.insert($0.lastPathComponent).inserted }
            // Listed under the folder, never under whatever the frontmatter calls itself:
            // the folder is the name an agent asks for, and a SKILL.md claiming another
            // skill's name would put a row in the picker that resolves to that other one.
            .map { folder in
                SkillDoc.load(
                    at: folder.appendingPathComponent("SKILL.md"),
                    named: folder.lastPathComponent
                ).named(folder.lastPathComponent)
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Installing from a git repo

    /// A remote worth handing to `git clone`. The arguments go straight to the process,
    /// never through a shell, so this is not about quoting: it is about a "URL" that is
    /// really a git option (`--upload-pack=…`) or a local path to somewhere else on disk.
    package static func isRemote(_ text: String) -> Bool {
        let remote = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.contains(" "), remote.count > 8 else { return false }
        return ["https://", "http://", "ssh://", "git@"].contains { remote.hasPrefix($0) }
    }

    /// Every skill in a checkout. A repo is sometimes one skill (`SKILL.md` at its root),
    /// sometimes a folder of them, sometimes keeps them under `skills/` — finding the
    /// folders that hold a `SKILL.md` covers all three without inventing a convention.
    static func skillFolders(in checkout: URL, depth: Int = 3) -> [URL] {
        let fm = FileManager.default
        if fm.fileExists(atPath: checkout.appendingPathComponent("SKILL.md").path) { return [checkout] }
        guard depth > 0 else { return [] }
        let children =
            ((try? fm.contentsOfDirectory(
                at: checkout,
                includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return children.flatMap { skillFolders(in: $0, depth: depth - 1) }
    }

    /// What a skill folder installs as: the name its own frontmatter claims, since that
    /// is the name an agent asks for, falling back to the folder it arrived in.
    static func installName(of folder: URL) -> String {
        let fallback = folder.lastPathComponent
        let text = (try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        let named = SkillDoc.parse(text, named: fallback).name
        let slug = NotebookFormat.slug(named)
        return slug.isEmpty ? NotebookFormat.slug(fallback) : slug
    }

    /// Clones a repo and installs every skill in it into the project, returning their
    /// names. A skill already there under the same name is replaced — pointing the field
    /// at the same repo again is how you update one.
    ///
    /// ponytail: synchronous, like every other `git` call in the app. A shallow clone of
    /// a skills repo is a second or two of a modal sheet; move it off the main thread if
    /// someone points it at a repo that is actually big.
    package static func install(git remote: String, into project: URL) throws -> [String] {
        let url = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isRemote(url) else {
            throw error("Not a git remote. Use an https:// or ssh:// URL, or git@host:owner/repo.")
        }
        let fm = FileManager.default
        let checkout = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-clone-\(UUID().uuidString)")
            .appendingPathComponent(repositoryName(url))
        defer { try? fm.removeItem(at: checkout.deletingLastPathComponent()) }

        let failure = clone(url, into: checkout)
        guard failure == nil else { throw error("git clone failed.\n\n\(failure!)") }

        let found = skillFolders(in: checkout)
        guard !found.isEmpty else {
            throw error("No SKILL.md anywhere in \(repositoryName(url)) — that repo holds no skills.")
        }
        let destination = project.appendingPathComponent(folders[0])
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var installed: [String] = []
        for folder in found {
            let name = installName(of: folder)
            let target = destination.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: folder, to: target)
            try? fm.removeItem(at: target.appendingPathComponent(".git"))
            link(name, in: project)
            installed.append(name)
        }
        return installed
    }

    /// The Codex half: `.agents/skills/<name>` pointing at the copy under `.claude`, the
    /// same relative link the app's own skills folder uses, so one edit serves both CLIs.
    private static func link(_ name: String, in project: URL) {
        let fm = FileManager.default
        let mirror = project.appendingPathComponent(folders[1])
        try? fm.createDirectory(at: mirror, withIntermediateDirectories: true)
        let link = mirror.appendingPathComponent(name)
        guard (try? link.checkResourceIsReachable()) != true,
            (try? fm.destinationOfSymbolicLink(atPath: link.path)) == nil
        else { return }
        try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: "../../\(folders[0])/\(name)")
    }

    /// nil when the clone worked, git's own complaint when it did not.
    private static func clone(_ remote: String, into checkout: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // `--` so a remote that still slipped past validation is read as a path, not a flag.
        task.arguments = ["git", "clone", "--depth", "1", "--quiet", "--", remote, checkout.path]
        let pipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = pipe
        do { try task.run() } catch { return error.localizedDescription }
        let complaint = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        task.waitUntilExit()
        guard task.terminationStatus != 0 else { return nil }
        return complaint.isEmpty ? "git exited \(task.terminationStatus)." : complaint
    }

    static func repositoryName(_ remote: String) -> String {
        let trimmed = remote.hasSuffix("/") ? String(remote.dropLast()) : remote
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? "skills"
        let name = last.hasSuffix(".git") ? String(last.dropLast(4)) : last
        let slug = NotebookFormat.slug(name)
        return slug.isEmpty ? "skills" : slug
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "Skills", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
