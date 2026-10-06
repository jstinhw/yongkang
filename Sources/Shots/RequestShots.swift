import SwiftUI
import YongkangCore
import YongkangUI

extension DesignShots {
    /// The board's request box with a request half typed, and the board once Product has filed
    /// one: the sample's Vercel milestone stands in for what it wrote.
    @MainActor static func writeRequestShots(_ project: Project, agents: AgentChoice, into directory: URL) {
        let others = [
            Mention.Project(tag: "/notebook-sync/", directory: URL(fileURLWithPath: "/tmp/notebook-sync")),
            Mention.Project(tag: "../personal/blog/", directory: URL(fileURLWithPath: "/tmp/blog")),
        ]
        let typed =
            "The download page should say when the notebook last synced. Read it from @/notebook-sync and show it "
            + "beside the button in @app/download/page.tsx, styled like the build badge on @../personal/blog"
        write(
            console(project, section: .board) {
                board(
                    project, agents: agents,
                    dock: AnyView(
                        RequestDock(
                            root: project.directory, projects: others, followUp: false, text: .constant(typed),
                            agents: agents, send: { _ in }, close: {})))
            }, "board-request", into: directory)

        let filed = project.cards.filter { $0.id == "ship-the-site" || $0.project == "ship-the-site" }
        write(
            console(project, section: .board) {
                VStack(spacing: 0) {
                    RequestBanner(filed: filed, openSession: {}, askForChanges: {}, approve: {}, dismiss: {})
                    board(project, agents: agents, fresh: Set(filed.map(\.id)))
                }
            }, "board-filed", into: directory)

        // Product's session once it has stopped, where the request is approved or sent back too.
        var asked = project
        let product = CodeSession(title: "Product", icon: "sparkles", line: "claude", agent: .claude, idle: true)
        asked.sessions.append(product)
        write(
            console(asked, section: .agents, selection: .session(product.id)) {
                AgentPage(
                    session: product, project: asked,
                    row: asked.agentRows(summary: ChangeSummary(), asking: [:]).first {
                        $0.route == .session(product.id)
                    },
                    openBlock: { _ in },
                    content: {
                        VStack(spacing: 0) {
                            RequestBanner(filed: filed, openSession: nil, askForChanges: {}, approve: {}, dismiss: {})
                            Theme.bg
                        }
                    })
            }, "session-request", into: directory)

        writeCrossProjectShots(project, filed: filed, agents: agents, into: directory)

        // A board with nothing on it yet, where the request is most of what there is to do.
        let notebook = project.cards.filter { $0.kind != .task && $0.kind != .project }
        write(
            console(project, section: .board) {
                NotebookBoard(
                    cards: notebook, blocks: [], assigned: [], reviewing: [], showDone: false, agents: agents,
                    assign: { _, _ in }, review: {}, openCard: { _ in }, openBlock: { _ in },
                    openReview: { _ in }, remove: { _ in }, request: {})
            }, "board-empty", into: directory)

        writeSetupShots(project, agents: agents, into: directory)
    }

    /// A request that needs a part from another open project, as each side shows it: the asking
    /// board while it waits, the other project's Product asked by it, that project's board with
    /// what it filed, and the asking board once the answer is in. The sample asks notebook-sync.
    @MainActor private static func writeCrossProjectShots(
        _ project: Project, filed: [NotebookCard], agents: AgentChoice, into directory: URL
    ) {
        let asked = (project: "notebook-sync", title: "Last sync time for the download page")
        write(
            console(project, section: .board) {
                VStack(spacing: 0) {
                    RequestBanner(
                        filed: [], asked: asked, waiting: true, openSession: {}, askForChanges: {}, dismiss: {})
                    board(project, agents: agents)
                }
            }, "board-waiting", into: directory)

        // Its turn is over while it waits, which reads as at work rather than as your turn.
        var asking = project
        let waiting = CodeSession(title: "Product", icon: "sparkles", line: "claude", agent: .claude, idle: true)
        asking.sessions.append(waiting)
        asking.peers = [waiting.id: .waitingOn("notebook-sync")]
        var sync = Project(directory: URL(fileURLWithPath: "/Users/you/sources/notebook-sync"), entries: [])
        let product = CodeSession(title: "Product", icon: "sparkles", line: "claude", agent: .claude)
        sync.sessions = [
            CodeSession(title: "Claude Code", icon: "sparkles", line: "claude", agent: .claude, taskIDs: ["resume"]),
            product,
        ]
        sync.peers = [product.id: .askedBy(project.name)]
        let synced = ChangeSummary(tasks: [
            SummaryTask(id: "resume", title: "Resume sync after sleep", status: "active")
        ])
        write(
            console(
                sync, section: .agents, summary: synced, selection: .session(product.id),
                others: [SidebarProject(project: asking, summary: ChangeSummary())]
            ) {
                AgentPage(
                    session: product, project: sync,
                    row: sync.agentRows(summary: synced).first { $0.route == .session(product.id) },
                    openBlock: { _ in }, content: { Theme.bg })
            }, "session-asked", into: directory)

        // The sample as the asked board here, with what its Product filed for yongkang-site.
        write(
            console(project, section: .board) {
                VStack(spacing: 0) {
                    RequestBanner(
                        filed: filed, from: "yongkang-site", openSession: {}, askForChanges: {}, approve: {},
                        dismiss: {})
                    board(project, agents: agents, fresh: Set(filed.map(\.id)))
                }
            }, "board-asked", into: directory)

        let own = filed.filter { $0.kind == .task }.prefix(1)
        write(
            console(project, section: .board) {
                VStack(spacing: 0) {
                    RequestBanner(
                        filed: Array(own), asked: asked, openSession: {}, askForChanges: {}, approve: {}, dismiss: {})
                    board(project, agents: agents, fresh: Set(own.map(\.id)))
                }
            }, "board-answered", into: directory)
    }

    @MainActor private static func board(
        _ project: Project, agents: AgentChoice, fresh: Set<String> = [], dock: AnyView? = nil
    ) -> NotebookBoard {
        NotebookBoard(
            cards: project.cards, blocks: project.blocks, assigned: project.assignedTaskIDs, reviewing: [],
            showDone: false, agents: agents, assign: { _, _ in }, review: {}, openCard: { _ in },
            openBlock: { _ in }, openReview: { _ in }, remove: { _ in }, fresh: fresh, request: {}, dock: dock)
    }
}
