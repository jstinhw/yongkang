import Foundation
import Testing

@testable import Yongkang

@Suite struct ServiceTests {
    /// Copies files out of `Fixtures/compose/<folder>/` into `dir`, keeping their paths.
    private func place(_ files: [String], from folder: String, into dir: URL) throws {
        for file in files {
            let target = dir.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try fixture("compose/\(folder)/\(file)").write(to: target, atomically: true, encoding: .utf8)
        }
    }

    struct Detection: Sendable, CustomTestStringConvertible {
        let files: [String]
        let command: String?
        let why: String
        var testDescription: String { files.isEmpty ? "empty folder" : files.joined(separator: " + ") }
    }

    // A repo says how it starts, and compose wins over the app it brings up with it.
    @Test(arguments: [
        Detection(files: [], command: nil, why: "an empty folder has nothing to run"),
        Detection(
            files: ["package.json"], command: "npm run dev",
            why: "the script has to come out of scripts, not any key that reads like one"),
        Detection(
            files: ["package.json", "compose.yaml"], command: "docker compose up",
            why: "compose starts the database the app needs, so it wins"),
    ])
    func commandComesFromTheRepo(_ row: Detection) throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try place(row.files, from: "c-web", into: repo)
        #expect(Service.command(in: repo) == row.command, "\(row.why)")
    }

    @Test func reposResolveAgainstTheProject() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let repo = tmp.appendingPathComponent("web")
        try place(["package.json"], from: "c-web", into: repo)

        #expect(Service.directory("~/x", in: tmp).path == NSString(string: "~/x").expandingTildeInPath)
        #expect(Service.directory("web", in: tmp).path == repo.path)
        #expect(Service.isFrontend(repo), "a package.json is the preview's frontend signal")
        #expect(
            !Service.isFrontend(tmp.appendingPathComponent("api")),
            "a repo with no package.json is not treated as a frontend app")
    }

    @Test func planCoversEveryRepo() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try place(["package.json", "compose.yaml"], from: "c-web", into: tmp.appendingPathComponent("web"))

        let hasRepos = NotebookCard(
            id: "p", url: tmp, kind: .project, title: "P", status: "todo",
            project: nil, dependsOn: [], repos: ["web", "api"])
        let plan = Service.plan(for: hasRepos, in: tmp)
        try #require(plan.map(\.repo) == ["web", "api"])
        #expect(
            plan[0].services.count == 1 && plan[1].services.count == 1,
            "no monorepo split and no named compose services is one service each")
        #expect(
            plan[0].services.first?.command == "docker compose up" && plan[1].services.first?.command == nil,
            "a repo that is not there yet is reported, not dropped")
        let noRepos = NotebookCard(
            id: "p", url: tmp, kind: .project, title: "P", status: "todo",
            project: nil, dependsOn: [])
        #expect(
            Service.plan(for: noRepos, in: tmp).map(\.directory.path) == [tmp.path],
            "a project without repos is its own folder")
    }

    // Several notebook projects with no repos: of their own all fall back to the same
    // project root — that must collapse to one preview row, not one per project.
    @Test func projectsSharingAFolderAreOnePreview() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let noRepos = NotebookCard(
            id: "p", url: tmp, kind: .project, title: "P", status: "todo",
            project: nil, dependsOn: [])

        let sameFolder = [noRepos, noRepos, noRepos].flatMap { Service.plan(for: $0, in: tmp) }
        #expect(sameFolder.count == 3, "the bug reproduces: three project cards, three plan entries")
        #expect(
            Service.dedupedByDirectory(sameFolder).count == 1,
            "three project cards pointing at the same folder is one preview, not three")
        let twoRepos = NotebookCard(
            id: "p2", url: tmp, kind: .project, title: "P2", status: "todo",
            project: nil, dependsOn: [], repos: ["web", "api"])
        let mixed = Service.dedupedByDirectory(sameFolder + Service.plan(for: twoRepos, in: tmp))
        #expect(
            mixed.map(\.repo) == [tmp.lastPathComponent, "web", "api"],
            "a distinct repo is kept, only the duplicate root collapses")
    }

    struct Layout: Sendable, CustomTestStringConvertible {
        let name: String
        let folder: String
        let files: [String]
        let services: [String]
        let commands: [String?]
        let why: String
        var testDescription: String { name }
    }

    // A monorepo's apps/ folder names each service on its own, independently runnable.
    // A compose file names its own services too, one `docker compose up <name>` each.
    // apps/ is the more specific signal — it wins even when a root compose file is also there.
    @Test(arguments: [
        Layout(
            name: "apps/ monorepo", folder: "c-mono",
            files: ["apps/api/go.mod", "apps/web/package.json"],
            services: ["api", "web"], commands: ["go run .", "npm run dev"],
            why: "apps/ names each service, sorted"),
        Layout(
            name: "compose services", folder: "c-composed", files: ["docker-compose.yml"],
            services: ["web", "worker"], commands: ["docker compose up web", "docker compose up worker"],
            why: "compose names its own services"),
        Layout(
            name: "apps/ beside a root compose", folder: "c-mono",
            files: ["apps/api/go.mod", "apps/web/package.json", "docker-compose.yml"],
            services: ["api", "web"], commands: ["go run .", "npm run dev"],
            why: "a monorepo split wins over a root compose file"),
    ])
    func servicesUnderARepo(_ layout: Layout) throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try place(layout.files, from: layout.folder, into: repo)

        let found = Service.services(in: repo)
        #expect(found.map(\.name) == layout.services, "\(layout.why)")
        #expect(found.map(\.command) == layout.commands)
    }

    @Test func serviceLineRunsInItsDirectory() {
        #expect(AgentCommand.line(directory: "/a b", run: "npm run dev") == "cd '/a b' && npm run dev")
    }

    // An agent can leave package.json half-written. Today that reads as no npm script
    // rather than a crash, the next signal down still gets its turn, and presence alone
    // keeps it a frontend.
    @Test func invalidPackageJSONFallsThrough() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try place(["package.json"], from: "c-invalid-package-json", into: repo)

        #expect(Service.command(in: repo) == nil, "unparseable JSON is no script, not a crash")
        #expect(Service.isFrontend(repo), "the frontend signal is the file being there, not parsing")
        try "module x\n".write(to: repo.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        #expect(Service.command(in: repo) == "go run .", "a broken package.json does not hide go.mod")
        #expect(Service.services(in: repo).map(\.command) == ["go run ."])
    }
}
