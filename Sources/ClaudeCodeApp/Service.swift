import Foundation

/// What it takes to look at a project working. A repo already says how it starts — a
/// compose file, an npm script, a Cargo manifest — so nothing here is configured until a
/// repo needs something the convention does not cover. A project listing a web app and
/// the service behind it gets both, because reviewing the front end means the back end
/// has to be up.
enum Service {
    /// A `repos:` entry resolved against the project folder. Absolute paths and `~` are
    /// left alone; everything else is relative to the folder the agents run in.
    static func directory(_ repo: String, in project: URL) -> URL {
        let expanded = NSString(string: repo).expandingTildeInPath
        guard !expanded.hasPrefix("/") else { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return project.appendingPathComponent(expanded).standardizedFileURL
    }

    /// The command that brings the repo up, or nil if it does not look runnable. Compose
    /// wins where both exist: it starts the databases the app needs, not just the app.
    static func command(in directory: URL) -> String? {
        func path(_ name: String) -> String { directory.appendingPathComponent(name).path }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: path(name)) }

        if exists("docker-compose.yml") || exists("docker-compose.yaml") || exists("compose.yaml") {
            return "docker compose up"
        }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("package.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: Any] {
            if let name = ["dev", "start", "serve"].first(where: { scripts[$0] != nil }) {
                return "npm run \(name)"
            }
        }
        if exists("Cargo.toml") { return "cargo run" }
        if exists("go.mod") { return "go run ." }
        if let makefile = try? String(contentsOf: directory.appendingPathComponent("Makefile"), encoding: .utf8),
           let target = ["dev", "run", "serve"].first(where: { makefile.contains("\n\($0):") || makefile.hasPrefix("\($0):") }) {
            return "make \(target)"
        }
        return nil
    }

    /// Every runnable repo of a project, in the order they are listed. A project with no
    /// `repos:` is its own repo — the common case where the work lands in the folder the
    /// notebook lives in.
    static func plan(for card: NotebookCard, in project: URL) -> [(repo: String, directory: URL, command: String?)] {
        let repos = card.repos.isEmpty ? ["."] : card.repos
        return repos.map { repo in
            let directory = directory(repo, in: project)
            return (repo == "." ? project.lastPathComponent : repo, directory, command(in: directory))
        }
    }
}
