import Foundation

/// What it takes to look at a project working. A repo already says how it starts — a
/// compose file, an npm script, a Cargo manifest — so nothing here is configured until a
/// repo needs something the convention does not cover. A project listing a web app and
/// the service behind it gets both, because reviewing the front end means the back end
/// has to be up.
///
/// A repo is not always one app: a monorepo holds several under `apps/` or `services/`,
/// and a compose file usually names more than one. Either way the repo is asked what runs
/// under it, and each answer is its own independently runnable service.
enum Service {
    typealias Runnable = (name: String, directory: URL, command: String?)

    /// A `repos:` entry resolved against the project folder. Absolute paths and `~` are
    /// left alone; everything else is relative to the folder the agents run in.
    static func directory(_ repo: String, in project: URL) -> URL {
        let expanded = NSString(string: repo).expandingTildeInPath
        guard !expanded.hasPrefix("/") else { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return project.appendingPathComponent(expanded).standardizedFileURL
    }

    /// The command that brings one directory up, or nil if it does not look runnable.
    static func command(in directory: URL) -> String? {
        func path(_ name: String) -> String { directory.appendingPathComponent(name).path }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: path(name)) }

        if exists("docker-compose.yml") || exists("docker-compose.yaml") || exists("compose.yaml") {
            return "docker compose up"
        }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("package.json")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = json["scripts"] as? [String: Any]
        {
            if let name = ["dev", "start", "serve"].first(where: { scripts[$0] != nil }) {
                return "npm run \(name)"
            }
        }
        if exists("Cargo.toml") { return "cargo run" }
        if exists("go.mod") { return "go run ." }
        if let makefile = try? String(contentsOf: directory.appendingPathComponent("Makefile"), encoding: .utf8),
            let target = ["dev", "run", "serve"].first(where: {
                makefile.contains("\n\($0):") || makefile.hasPrefix("\($0):")
            })
        {
            return "make \(target)"
        }
        return nil
    }

    /// What actually runs under a repo, each independently. A monorepo's `apps/` or
    /// `services/` folder wins when present — that is the explicit signal there is more
    /// than one app here. Next, a compose file's own service names. Neither means the repo
    /// is one app, and the repo itself is the service.
    static func services(in directory: URL) -> [Runnable] {
        let monorepo = monorepoServices(in: directory)
        if !monorepo.isEmpty { return monorepo }
        let compose = composeServiceNames(in: directory)
        if !compose.isEmpty {
            return compose.map { (name: $0, directory: directory, command: "docker compose up \($0)") }
        }
        return [(name: directory.lastPathComponent, directory: directory, command: command(in: directory))]
    }

    private static func monorepoServices(in directory: URL) -> [Runnable] {
        let fm = FileManager.default
        return ["apps", "services"].flatMap { group -> [Runnable] in
            let groupDir = directory.appendingPathComponent(group)
            guard
                let children = try? fm.contentsOfDirectory(at: groupDir, includingPropertiesForKeys: [.isDirectoryKey])
            else { return [] }
            return
                children
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { (name: $0.lastPathComponent, directory: $0, command: command(in: $0)) }
        }
    }

    // ponytail: 2-space top-level indent under `services:`, docker's own convention — not a
    // YAML parser. A compose file indented some other way falls back to the single command.
    private static func composeServiceNames(in directory: URL) -> [String] {
        let candidates = ["docker-compose.yml", "docker-compose.yaml", "compose.yaml"]
        guard
            let file = candidates.first(where: {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
            }),
            let text = try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
        else { return [] }

        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "services:" })
        else { return [] }

        var names: [String] = []
        for line in lines[(start + 1)...] {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard line.hasPrefix("  ") else { break }
            guard !line.hasPrefix("   ") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            names.append(String(line[line.index(line.startIndex, offsetBy: 2)..<colon]))
        }
        return names
    }

    /// Every repo of a project, in the order they are listed, each with what runs under
    /// it. A project with no `repos:` is its own repo — the common case where the work
    /// lands in the folder the notebook lives in.
    static func plan(for card: NotebookCard, in project: URL) -> [(repo: String, directory: URL, services: [Runnable])]
    {
        let repos = card.repos.isEmpty ? ["."] : card.repos
        return repos.map { repo in
            let directory = directory(repo, in: project)
            let label = repo == "." ? project.lastPathComponent : repo
            return (label, directory, services(in: directory))
        }
    }

    /// Keeps the first repo at each resolved directory. Several notebook projects can
    /// legitimately point at the same folder — a single app split across several project
    /// entries, or two that never filled in `repos:` and both fell back to the project
    /// root — and that must not read as several copies of the same app.
    static func dedupedByDirectory(
        _ steps: [(repo: String, directory: URL, services: [Runnable])]
    )
        -> [(repo: String, directory: URL, services: [Runnable])]
    {
        var seen: Set<String> = []
        return steps.filter { seen.insert($0.directory.path).inserted }
    }

    // ponytail: package.json presence, not real frontend detection. Good enough — a Node
    // backend without a UI is a false positive, and the preview just has nothing to load.
    static func isFrontend(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("package.json").path)
    }
}
