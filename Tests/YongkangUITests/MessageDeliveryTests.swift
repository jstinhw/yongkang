import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// A message an agent writes to another open project, typed into the session it is for: that
/// project's Product for a first message, the session `reply_to` names for an answer, and the
/// sender itself when no project is open at `to`. Two folders, `site` asking and `sync` asked.
///
/// Serialized because the last test types into real `/bin/sh` PTYs, whose output arrives as
/// main-queue jobs — as in `TerminalRegistryTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct MessageDeliveryTests {
    /// `site` and `sync` in `tmp`, each with a notebook — and with `git`, a repo whose notebook is
    /// committed, so what Product files there is all a request has to approve.
    private func folders(in tmp: URL, git: Bool = false) async throws -> (site: URL, sync: URL) {
        let (site, sync) = (tmp.appendingPathComponent("site"), tmp.appendingPathComponent("sync"))
        for folder in [site, sync] {
            _ = try NotebookFormat.create(.task, title: "Base", in: NotebookFormat.root(in: folder), project: nil)
            guard git else { continue }
            try await repository(folder)
            #expect(await GitClient.commit(message: "Base", in: folder) == nil)
        }
        return (site, sync)
    }

    private func read(_ directory: URL) async -> ProjectModel {
        let project = ProjectModel(directory: directory)
        await project.reloadNotebook(frontmatter: true, records: true)
        return project
    }

    /// `.notebook/messages/<slug>.md` in `project`, the way the reading note tells an agent to
    /// write it, and the notebook read again.
    private func write(
        _ slug: String, to: String, session: UUID, replyTo: UUID? = nil, in project: ProjectModel
    ) async throws {
        let folder = project.notebookRoot.appendingPathComponent("messages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        ---
        kind: message
        to: "\(to)"
        session: \(session.uuidString.lowercased())
        reply_to: "\(replyTo?.uuidString.lowercased() ?? "")"
        title: "Sync time: \(slug)"
        created: 2026-10-06T12:00:00Z
        ---

        Expose when the last sync finished.
        """.write(to: folder.appendingPathComponent("\(slug).md"), atomically: true, encoding: .utf8)
        await project.reloadNotebook(frontmatter: true, records: true)
    }

    /// One poll's delivery across every project, as `AppModel.deliverMessages` runs it.
    private func deliver(_ projects: [ProjectModel], skipping delivered: inout Set<String>) -> [Delivery] {
        let routed = projects.flatMap { $0.deliveries(among: projects, skipping: delivered, agent: .claude) }
        delivered.formUnion(routed.map(\.key))
        return routed
    }

    @Test func aFirstMessageOpensProductThereAndEachBoardCommitsOnlyItsOwnPart() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (siteFolder, syncFolder) = try await folders(in: tmp, git: true)
        let (site, sync) = (await read(siteFolder), await read(syncFolder))
        _ = site.sendRequest("Show the sync time", projects: [], agent: .claude)
        let asking = try #require(site.sessions.first)
        var delivered: Set<String> = []

        try await write("ask", to: "../sync", session: asking.id, in: site)
        let first = deliver([site, sync], skipping: &delivered)
        let product = try #require(sync.sessions.first)
        #expect(product.isProduct && sync.sessions.count == 1, "a Product opens under the asked project")
        #expect(product.line.contains("asked") && product.line.contains("session \(asking.id.uuidString.lowercased())"))
        #expect(product.reading == [siteFolder], "and may read the asking project, to ask it back")
        #expect(first.map(\.session) == [product.id] && first.first?.text == nil, "started on it, nothing to type")
        #expect(sync.request?.session == product.id && sync.request?.from == siteFolder, "a request, and who asked")
        #expect(site.waitingOn == [asking.id: syncFolder], "the asking session waits on the answer")
        #expect(deliver([site, sync], skipping: &delivered).isEmpty, "the next read types nothing again")

        // Each Product files its own part on its own board, and sync's answers the session that asked.
        _ = try NotebookFormat.create(.task, title: "Record the sync time", in: sync.notebookRoot, project: nil)
        _ = try NotebookFormat.create(.task, title: "Show the sync time", in: site.notebookRoot, project: nil)
        try await write("answer", to: "../site", session: product.id, replyTo: asking.id, in: sync)
        await site.reloadNotebook(frontmatter: true, records: true)
        let answer = deliver([site, sync], skipping: &delivered)
        #expect(
            answer
                == [
                    Delivery(
                        key: try #require(sync.snapshot.messages.first).deliveryKey, session: asking.id,
                        text: NotebookFormat.incomingMessage(
                            from: "../sync", session: product.id.uuidString.lowercased(),
                            title: "Sync time: answer", body: "Expose when the last sync finished."))
                ], "the answer is typed into the session it names, as it is")
        #expect(site.waitingOn.isEmpty && sync.sessions.count == 1)
        #expect(
            sync.filed.map(\.title) == ["Record the sync time"] && site.filed.map(\.title) == ["Show the sync time"])

        _ = sync.markIdle(product.id, true)
        await sync.refreshRepo()
        #expect(sync.requestFinished)
        _ = try await sync.approveRequest()
        #expect(sync.repo.head?.hasSuffix("Plan Record the sync time") == true)
        await site.refreshRepo()
        #expect(site.planChanges.contains { $0.hasSuffix("show-the-sync-time.md") }, "the asking board's part waits")

        _ = site.markIdle(asking.id, true)
        _ = try await site.approveRequest()
        #expect(site.repo.head?.hasSuffix("Plan Show the sync time") == true)
        #expect(site.planChanges.isEmpty)
        await sync.refreshRepo()
        #expect(sync.repo.head?.hasSuffix("Plan Record the sync time") == true, "and commits nothing of sync's")
    }

    @Test func aMessageToARunningProductIsTypedIntoItAndKeepsItsRequest() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (siteFolder, syncFolder) = try await folders(in: tmp)
        let (site, sync) = (await read(siteFolder), await read(syncFolder))
        _ = sync.sendRequest("Tidy the log", projects: [], agent: .claude)
        let product = try #require(sync.sessions.first)
        let request = sync.request
        var delivered: Set<String> = []

        // An answer to a session that has gone is a first message, as one with no reply_to is.
        try await write("ask", to: "../sync/", session: UUID(), replyTo: UUID(), in: site)
        let typed = deliver([site, sync], skipping: &delivered)
        #expect(typed.map(\.session) == [product.id] && sync.sessions.count == 1, "one Product per project")
        #expect(typed.first?.text?.contains("asked\nA message from the project in `../site`") == true)
        #expect(sync.request == request, "what it filed for the board's own request is still new")
    }

    @Test func aMessageToNoOpenProjectIsAnsweredInTheSessionThatWroteIt() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (siteFolder, _) = try await folders(in: tmp)
        let site = await read(siteFolder)
        let id = UUID()
        _ = site.addSession(.claude, id: id, title: "Wire auth", taskIDs: ["base"])
        var delivered: Set<String> = []

        try await write("gone", to: "../blog", session: UUID(), in: site)
        #expect(deliver([site], skipping: &delivered).isEmpty, "with nobody to tell, it waits for a later read")

        try await write("ask", to: "../sync", session: id, in: site)
        let answer = try #require(deliver([site], skipping: &delivered).first)
        #expect(answer.session == id)
        #expect(
            answer.text
                == "Not delivered: no project open in Yongkang is at `../sync`, so nobody read "
                + ".notebook/messages/ask.md. Ask the user to open that project, or carry on without its answer.")
        #expect(deliver([site], skipping: &delivered).isEmpty, "said once")
        #expect(site.waitingOn.isEmpty)
    }

    /// What the sidebar, a session's header and the board's banner say about the other project:
    /// the asking Product waits on it, the asked one was asked by it, and once the answer is in
    /// the asking board says that project filed its part.
    @Test func eachSideSaysWhoItIsTalkingTo() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (siteFolder, syncFolder) = try await folders(in: tmp, git: true)
        let (site, sync) = (await read(siteFolder), await read(syncFolder))
        _ = site.sendRequest("Show the sync time", projects: [], agent: .claude)
        let asking = try #require(site.sessions.first)
        var delivered: Set<String> = []

        // Product files what does not wait on the answer, asks, and its turn ends.
        _ = try NotebookFormat.create(.task, title: "Show the sync time", in: site.notebookRoot, project: nil)
        try await write("ask", to: "../sync", session: asking.id, in: site)
        _ = deliver([site, sync], skipping: &delivered)
        let product = try #require(sync.sessions.first)
        _ = site.markIdle(asking.id, true)
        await site.refreshRepo()
        let waiting = try #require(site.value.agentRows(summary: ChangeSummary()).first)
        #expect(waiting.state == .working && waiting.line == "waiting on sync", "the next move is sync's, not yours")
        #expect(site.requestWaitsOn == BoardRequest.Ask(project: syncFolder, title: "Sync time: ask"))
        #expect(!site.requestFinished, "its plan waits on the answer")
        let asked = try #require(sync.value.agentRows(summary: ChangeSummary()).first)
        #expect(asked.peer == .askedBy("site") && asked.line == "asked by site")

        // sync files its part and answers; what its Product wrote back is not a question it waits on.
        _ = try NotebookFormat.create(.task, title: "Record the sync time", in: sync.notebookRoot, project: nil)
        try await write("answer", to: "../site", session: product.id, replyTo: asking.id, in: sync)
        await site.reloadNotebook(frontmatter: true, records: true)
        _ = deliver([site, sync], skipping: &delivered)
        _ = sync.markIdle(product.id, true)
        await sync.refreshRepo()
        #expect(sync.peers == [product.id: .askedBy("site")] && sync.requestFinished)
        #expect(
            sync.value.agentRows(summary: ChangeSummary()).first?.state == .needsYou, "its plan is yours to approve")
        #expect(site.requestWaitsOn == nil && site.request?.asked?.project == syncFolder, "who answered is kept")
        #expect(site.peers.isEmpty && site.requestFinished)
    }

    @Test func theBannerNamesTheOtherProjectInBold() {
        let task = NotebookCard(
            id: "t", url: URL(fileURLWithPath: "/tmp/t.md"), kind: .task, title: "T", status: "todo", project: nil,
            dependsOn: [])
        let asked = (project: "sync", title: "Sync time")
        let lines = [
            RequestBanner.line(of: [], finished: false, asked: asked, waiting: true),
            RequestBanner.line(of: [task], finished: true, from: "site"),
            RequestBanner.line(of: [task], finished: true, asked: asked),
        ]
        #expect(
            lines.map { String($0.characters) } == [
                "Product is waiting on sync’s answer · asked “Sync time”",
                "Product filed site’s request as a task.",
                "Product filed your request as a task; sync filed its own part.",
            ])
        let bold = lines.map { line in line.runs.filter { $0.font != nil }.map { String(line[$0.range].characters) } }
        #expect(bold == [["sync"], ["site"], ["sync"]])
    }

    /// A CLI stand-in that appends every line typed into it to `log`.
    private func logger(_ log: URL) -> String {
        "while IFS= read -r line; do printf '%s\\n' \"$line\" >> '\(log.path)'; printf 'got it\\r\\n'; done"
    }

    /// What was typed into `log`'s session, once `end` — typed after everything else — is in.
    private func typed(into log: URL, model: AppModel, session: UUID) async throws -> [String] {
        model.terminals.send("end", to: session)
        let lines = {
            ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        #expect(try await eventually { lines().last == "\u{1b}[200~end\u{1b}[201~" })
        return lines().dropLast()
    }

    @Test func eachMessageIsTypedInOnceWithoutMovingTheWindowEvenAfterARelaunch() async throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (siteFolder, syncFolder) = try await folders(in: tmp)
        let (asking, product) = (UUID(), UUID())
        let model = AppModel(terminals: TerminalRegistry(shell: ["/bin/sh", "-c"]), notify: { _, _, _ in })
        let (site, sync) = (model.open(siteFolder), model.open(syncFolder))
        // Closing a project ends its sessions' shells, which would otherwise read forever.
        defer { for project in model.projects { model.close(project) } }
        site.addSession(
            id: asking, title: "Product", icon: "sparkles", line: logger(tmp.appendingPathComponent("site.log")))
        sync.addSession(
            id: product, title: "Product", icon: "sparkles", line: logger(tmp.appendingPathComponent("sync.log")))
        model.enter(site, at: .task("base"))
        await model.reloadNow()

        try await write("ask", to: "../sync", session: asking, in: site)
        try await write("lost", to: "../blog", session: asking, in: site)
        await model.reloadNow()
        try await write("answer", to: "../site", session: product, replyTo: asking, in: sync)
        await model.reloadNow()
        await model.reloadNow()
        #expect(model.entered === site && model.section == .board && model.selection == .task("base"))

        let atSync = try await typed(into: tmp.appendingPathComponent("sync.log"), model: model, session: product)
        #expect(atSync.filter { $0.contains("A message from the project in `../site`") }.count == 1, "\(atSync)")
        #expect(sync.request?.from == siteFolder, "typed into its running Product, as a request")
        let atSite = try await typed(into: tmp.appendingPathComponent("site.log"), model: model, session: asking)
        #expect(atSite.filter { $0.contains("A message from the project in `../sync`") }.count == 1, "\(atSite)")
        #expect(atSite.filter { $0.contains("Not delivered") }.count == 1, "\(atSite)")

        // What `RootView` keeps in defaults, read back by the next launch before its first read.
        let stored = OpenProjects.encode(model.deliveredMessages.sorted())
        let relaunched = AppModel(terminals: TerminalRegistry(shell: ["/bin/sh", "-c"]), notify: { _, _, _ in })
        relaunched.deliveredMessages = Set(OpenProjects.decode(stored))
        let (again, other) = (relaunched.open(siteFolder), relaunched.open(syncFolder))
        defer { for project in relaunched.projects { relaunched.close(project) } }
        again.addSession(
            id: asking, title: "Product", icon: "sparkles", line: logger(tmp.appendingPathComponent("a.log")))
        other.addSession(
            id: product, title: "Product", icon: "sparkles", line: logger(tmp.appendingPathComponent("b.log")))
        await relaunched.reloadNow()
        #expect(try await typed(into: tmp.appendingPathComponent("a.log"), model: relaunched, session: asking).isEmpty)
        #expect(try await typed(into: tmp.appendingPathComponent("b.log"), model: relaunched, session: product).isEmpty)
    }
}
