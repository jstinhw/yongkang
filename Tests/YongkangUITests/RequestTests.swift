import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// The board's request box: `@/` and `@../` name the other open projects the way the sidebar
/// groups them, the tags go to Product as paths it can open, and what Product files is told
/// apart from what was already on the board.
@MainActor @Suite struct RequestTests {

    /// `site` in Client work, beside `sync` in the same group, `blog` in Personal, and
    /// `yongkang` in no group.
    private func open(in tmp: URL) throws -> (here: URL, all: [(directory: URL, group: String?)]) {
        let folder = { (name: String) in tmp.appendingPathComponent(name) }
        for name in ["site", "sync/Sources", "blog", "yongkang"] {
            try FileManager.default.createDirectory(at: folder(name), withIntermediateDirectories: true)
        }
        try Data().write(to: folder("sync/Sources/SyncLog.swift"))
        try Data().write(to: folder("site/notes.md"))
        return (
            folder("site"),
            [
                (folder("site"), "Client work"), (folder("sync"), "Client work"),
                (folder("blog"), "Personal"), (folder("yongkang"), nil),
            ]
        )
    }

    @Test func tagsFollowTheSidebarGroups() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (here, all) = try open(in: tmp)

        let tags = Mention.projects(from: all, for: here, in: "Client work").map(\.tag)
        #expect(tags == ["/sync/", "../personal/blog/", "../yongkang/"])

        let loose = Mention.projects(from: all, for: all[3].directory, in: nil).map(\.tag)
        #expect(
            loose == ["../client-work/site/", "../client-work/sync/", "../personal/blog/"],
            "from a project in no group, every group is outside it")
    }

    @Test func matchesWalkProjectsThenTheirFiles() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (here, all) = try open(in: tmp)
        let projects = Mention.projects(from: all, for: here, in: "Client work")

        #expect(
            Mention.matches("", root: here, projects: projects) == ["/sync/", "../", "notes.md"],
            "a bare @ offers this group's projects, the way out of it, then this project's files")
        #expect(Mention.matches("../", root: here, projects: projects) == ["../personal/", "../yongkang/"])
        #expect(Mention.matches("../personal/", root: here, projects: projects) == ["../personal/blog/"])
        #expect(Mention.matches("/sy", root: here, projects: projects) == ["/sync/"])
        #expect(
            Mention.matches("/sync/Sources/", root: here, projects: projects) == ["/sync/Sources/SyncLog.swift"],
            "inside a project, its own files")
        #expect(
            Mention.matches("bl", root: here, projects: projects) == ["../personal/blog/"],
            "a bare name finds a project wherever it is")
        #expect(Mention.matches(".", root: here, projects: projects) == ["../"])
        #expect(
            Mention.matches("/", root: here, projects: []) == ["notes.md"],
            "with no projects, @/ is still the box's own folder")
        #expect(Mention.isGroup("../personal/", among: projects) && !Mention.isGroup("/sync/", among: projects))
    }

    @Test func tagsGoToTheAgentAsPathsItCanOpen() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (here, all) = try open(in: tmp)
        let projects = Mention.projects(from: all, for: here, in: "Client work")

        let (text, folders) = Mention.resolved(
            "Read @/sync/Sources/SyncLog.swift and @../personal/blog, change @notes.md, mail a@b.com @/nope",
            root: here, projects: projects)
        #expect(
            text == "Read @../sync/Sources/SyncLog.swift and @../blog/, change @notes.md, mail a@b.com @/nope",
            "a file here, an email address and a tag naming no project go as typed")
        #expect(folders.map(\.lastPathComponent) == ["sync", "blog"])
    }

    @Test func aRequestGoesToProductAndTheBoardStays() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (_, all) = try open(in: tmp)
        let directory = tmp.appendingPathComponent("site")
        _ = try NotebookFormat.create(
            .task, title: "Already here", in: NotebookFormat.root(in: directory), project: nil)
        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)
        project.requestOpen = true
        project.requestDraft = "Show the sync time from @/sync"

        let sent = project.sendRequest(
            project.requestDraft, projects: Mention.projects(from: all, for: directory, in: "Client work"),
            agent: .claude)
        let product = try #require(project.sessions.first)
        #expect(product.isProduct && product.line.contains("Show the sync time from @../sync/"))
        #expect(product.reading.map(\.lastPathComponent) == ["sync"], "Product is let into the tagged project")
        #expect(sent.input == nil, "a new session is started with the request, not typed into")
        #expect(project.request?.session == product.id)
        #expect(!project.requestOpen && project.requestDraft.isEmpty)
        #expect(project.filed.isEmpty && project.requestFollowsUp)

        _ = try NotebookFormat.create(
            .task, title: "Read the sync time", in: NotebookFormat.root(in: directory), project: nil)
        await project.reloadNotebook(frontmatter: true, records: true)
        #expect(project.filed.map(\.title) == ["Read the sync time"], "only what Product filed is new")

        let change = project.sendRequest("Split it in two", projects: [], agent: .codex)
        #expect(project.sessions.count == 1)
        #expect(
            change == Destination(section: .board, route: .session(product.id), input: "Split it in two"),
            "a change goes to the session on the request, as typed")
        #expect(project.filed.count == 1, "and the first request's new cards stay new")
    }

    @Test(
        arguments: [
            ([], "Product is on your request."),
            ([EntryKind.task], "Product filed your request as a task."),
            ([.project, .task, .task, .task], "Product filed your request as a milestone and 3 tasks."),
        ] as [([EntryKind], String)])
    func theBannerSaysWhatLanded(kinds: [EntryKind], line: String) throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = NotebookFormat.root(in: tmp)
        for (index, kind) in kinds.enumerated() {
            _ = try NotebookFormat.create(kind, title: "Entry \(index)", in: root, project: nil)
        }
        let cards = NotebookIndex.load(root: root)
        #expect(RequestBanner.summary(of: cards) == line)
    }
}
