import SwiftUI
import YongkangCore

/// One agent: what it is on and where it has got to, over its terminal or the page it drew.
/// Its page and what waits for your review are rows under it in the sidebar.
package struct AgentPage<Content: View>: View {
    let session: CodeSession
    let project: Project
    /// How the sidebar lists it, for its state and what it is doing. Nil once it has exited.
    let row: AgentRow?
    /// Opens the demo, block or proposal the row is waiting on you for.
    let openBlock: (UserBlock) -> Void
    @ViewBuilder let content: Content

    package init(
        session: CodeSession, project: Project, row: AgentRow?,
        openBlock: @escaping (UserBlock) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.session = session
        self.project = project
        self.row = row
        self.openBlock = openBlock
        self.content = content()
    }

    package var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
    }

    /// The task it is on: the row's, or the first of its chain.
    private var task: NotebookCard? {
        (row?.task ?? session.taskIDs.first).flatMap { id in project.cards.first { $0.id == id } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let row { AgentStateGlyph(state: row.state, size: 11) }
                    Text(status).font(Typography.caption(.semibold)).foregroundStyle(row?.state.color ?? Theme.tx3)
                }
                Text(task?.title ?? row?.request ?? session.title).font(Typography.title).foregroundStyle(Theme.tx)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    NotebookStyle.chip(project.name, mono: true)
                    // Who it is talking to, beside whose it is: the conversation is in its terminal.
                    if let peer = row?.peer {
                        NotebookStyle.chip {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold))
                                Text(
                                    "\(peer.verb) \(Text(peer.project).fontWeight(.semibold).foregroundStyle(Theme.tx))"
                                )
                            }
                            .font(Typography.caption)
                        }
                    }
                    if let task {
                        NotebookStyle.chip(task.id, mono: true)
                        Text(session.agent?.displayName ?? session.title)
                            .font(Typography.caption).foregroundStyle(Theme.tx3).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 12)
            // The sidebar row says "demo ready" and opens here, on the terminal; without this
            // the demo's approval was only reachable from the board.
            if row?.state == .needsYou, let block = row?.block {
                Button(BoardInspector.open(block)) { openBlock(block) }
                    .buttonStyle(.consolePrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var status: String {
        guard let row else { return session.exited ? "exited" : "idle" }
        return row.doing
    }
}
