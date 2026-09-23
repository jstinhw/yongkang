import SwiftUI
import YongkangCore

/// One agent: what it is on and where it has got to, over its terminal or the page it drew.
/// Its page and what waits for your review are rows under it in the sidebar.
package struct AgentPage<Content: View>: View {
    let session: CodeSession
    let project: Project
    /// How the sidebar lists it, for its state and what it is doing. Nil once it has exited.
    let row: AgentRow?
    @ViewBuilder let content: Content

    package init(
        session: CodeSession, project: Project, row: AgentRow?,
        @ViewBuilder content: () -> Content
    ) {
        self.session = session
        self.project = project
        self.row = row
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
                Text(session.title).font(Typography.title).foregroundStyle(Theme.tx)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    NotebookStyle.chip(project.name, mono: true)
                    if let task {
                        NotebookStyle.chip(task.id, mono: true)
                        Text("on \(task.title)").font(Typography.caption).foregroundStyle(Theme.tx3)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 12)
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
