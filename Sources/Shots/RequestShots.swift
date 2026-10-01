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
                    content: {
                        VStack(spacing: 0) {
                            RequestBanner(filed: filed, openSession: nil, askForChanges: {}, approve: {}, dismiss: {})
                            Theme.bg
                        }
                    })
            }, "session-request", into: directory)

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

    @MainActor private static func board(
        _ project: Project, agents: AgentChoice, fresh: Set<String> = [], dock: AnyView? = nil
    ) -> NotebookBoard {
        NotebookBoard(
            cards: project.cards, blocks: project.blocks, assigned: project.assignedTaskIDs, reviewing: [],
            showDone: false, agents: agents, assign: { _, _ in }, review: {}, openCard: { _ in },
            openBlock: { _ in }, openReview: { _ in }, remove: { _ in }, fresh: fresh, request: {}, dock: dock)
    }
}
