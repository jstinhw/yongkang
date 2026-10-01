import Foundation

/// Tagging the other open projects, the way the sidebar groups them: `@/name` is a project in
/// this one's own group, `@../group/name` one in another group, and `@../name` one in no group.
/// For a project in no group, its own group is the other loose projects — `/` is always the run
/// you are in, `../` everything outside it.
///
/// A project's tag is a folder, so Tab walks into its files the way it walks into any folder,
/// and a file in another project is `@/name/Sources/App.swift`. A box given no projects tags
/// the way it always has, and `@/De` there is still Desktop under its root.
extension Mention {
    /// One other project, by the tag that names it. The tag always ends in a slash.
    package struct Project: Equatable, Sendable {
        let tag: String
        let directory: URL

        package init(tag: String, directory: URL) {
            self.tag = tag
            self.directory = directory
        }
    }

    /// The tag for every project but `here`, as seen from `here`'s group.
    static func projects(from all: [(directory: URL, group: String?)], for here: URL, in group: String?) -> [Project] {
        all.filter { $0.directory.standardizedFileURL != here.standardizedFileURL }.map { other in
            let name = slug(other.directory.lastPathComponent)
            if other.group == group { return Project(tag: "/\(name)/", directory: other.directory) }
            if let theirs = other.group {
                return Project(tag: "../\(slug(theirs))/\(name)/", directory: other.directory)
            }
            return Project(tag: "../\(name)/", directory: other.directory)
        }
    }

    /// A name as a tag can carry it: a space would end the tag, so "Client work" is `client-work`.
    static func slug(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || "-_.".contains($0)) })
            .joined(separator: "-")
    }

    /// Everything a tag can complete to once other projects are taggable. Inside a project, that
    /// project's files; on `/` or `../`, the projects and groups one level down; on a bare name,
    /// the projects called that first and then this project's own files. With no projects, the
    /// same list `matches(_:root:)` gives.
    static func matches(_ query: String, root: URL, projects: [Project]) -> [String] {
        let lower = query.lowercased()
        if let project = projects.first(where: { lower.hasPrefix($0.tag) }) {
            return matches(String(query.dropFirst(project.tag.count)), root: project.directory).map { project.tag + $0 }
        }
        guard !projects.isEmpty else { return matches(query, root: root) }
        let levels = Set(projects.flatMap { folders(in: $0.tag) })
        let slash = lower.lastIndex(of: "/")
        let typed = slash.map { String(lower[lower.index(after: $0)...]) } ?? lower
        let up = levels.contains("../") && "../".hasPrefix(typed) ? ["../"] : []
        guard let slash else {
            let named = projects.map(\.tag).filter {
                typed.isEmpty ? $0.hasPrefix("/") : name(of: $0).hasPrefix(typed)
            }
            return named.sorted() + up + matches(query, root: root)
        }
        let folder = String(lower[...slash])
        guard folder.hasPrefix("/") || folder.hasPrefix("../") else { return matches(query, root: root) }
        let depth = folder.filter { $0 == "/" }.count + 1
        return levels.filter {
            $0.hasPrefix(folder) && $0.filter { $0 == "/" }.count == depth && name(of: $0).hasPrefix(typed)
        }
        .sorted()
    }

    /// A tag naming a group, or the `../` above them all, rather than a project or a file.
    static func isGroup(_ match: String, among projects: [Project]) -> Bool {
        !projects.contains { $0.tag == match } && projects.contains { $0.tag.hasPrefix(match) }
    }

    /// The prompt with every project tag turned into the path it names from `root`, which is
    /// what the agent can open: `@/notebook-sync/Sources` typed in `client-work/site` is sent as
    /// `@../notebook-sync/Sources`. Also the folders those tags reach into, so a CLI that has to
    /// be let into a folder outside its own is let in. A tag naming no project goes as typed, and
    /// the comma or full stop a sentence puts after a tag stays outside it.
    static func resolved(_ text: String, root: URL, projects: [Project]) -> (text: String, folders: [URL]) {
        var folders: [URL] = []
        let text = text.replacing(/(?<lead>^|[ \n])@(?<path>[^ \n]*[^ \n.,;:!?)])(?<tail>[.,;:!?)]*)/) { match in
            let path = String(match.path)
            guard let project = projects.first(where: { (path.lowercased() + "/").hasPrefix($0.tag) })
            else { return String(match.output.0) }
            if !folders.contains(project.directory) { folders.append(project.directory) }
            let inside = String(path.dropFirst(min(project.tag.count, path.count)))
            let target = inside.isEmpty ? project.directory : project.directory.appendingPathComponent(inside)
            let slash = inside.isEmpty || path.hasSuffix("/") ? "/" : ""
            return match.lead + "@" + relative(target, from: root) + slash + match.tail
        }
        return (text, folders)
    }

    /// `../a/b/` is three folders deep: `../`, `../a/` and `../a/b/`.
    private static func folders(in tag: String) -> [String] {
        tag.indices.filter { tag[$0] == "/" }.map { String(tag[...$0]) }
    }

    private static func name(of tag: String) -> String {
        tag.split(separator: "/").last.map(String.init) ?? ""
    }
}
