import SwiftUI
import YongkangCore

/// What came of the last request on this board: Product still on it, or what it filed, which
/// the board marks "new" until this is dismissed. The outcome, not the transcript — that is one
/// click away, under the session it ran in. Once Product's turn is over, what it filed is the
/// user's to approve, which commits it, or to send back with what to change.
///
/// A request that crosses projects names the other one: the project that asked for it, or the
/// one Product asked for its part — while the answer is still to come, and once it is in.
///
/// Under it, every agent on the request, one row each, whichever project it runs in: what each
/// is doing and has filed, one click from its session. The request is the thing being followed;
/// the sessions working it sat under two projects with nothing tying them together.
package struct RequestBanner: View {
    /// One agent on the request, as a row of the card.
    package struct Agent: Identifiable {
        package let id: String
        let name: String
        let project: String
        let state: AgentRow.State
        /// What it is doing, in a few words: "waiting on notebook-sync", "your turn".
        let doing: String
        /// What it has filed so far, in the board's words.
        let filed: String
        /// The Product of the project the request asked for its part, drawn under the one that asked.
        let asked: Bool
        /// Nil for the session the card is drawn on.
        let open: (() -> Void)?

        package init(
            id: String, name: String, project: String, state: AgentRow.State, doing: String, filed: String,
            asked: Bool, open: (() -> Void)?
        ) {
            self.id = id
            self.name = name
            self.project = project
            self.state = state
            self.doing = doing
            self.filed = filed
            self.asked = asked
            self.open = open
        }
    }

    /// What the request is called: the milestone it filed, or what was asked.
    let name: String?
    let agents: [Agent]
    let filed: [NotebookCard]
    /// The project that asked for this request, by name, when its message started it.
    let from: String?
    /// The project Product asked for its part, by name, with the title of what it asked.
    let asked: (project: String, title: String)?
    /// Whether that project's answer is still to come.
    let waiting: Bool
    /// Nil where the banner is drawn on that session already.
    let openSession: (() -> Void)?
    let askForChanges: () -> Void
    /// Nil until Product has filed something and stopped.
    let approve: (() -> Void)?
    let dismiss: () -> Void

    package init(
        name: String? = nil, agents: [Agent] = [],
        filed: [NotebookCard], from: String? = nil, asked: (project: String, title: String)? = nil,
        waiting: Bool = false, openSession: (() -> Void)?, askForChanges: @escaping () -> Void,
        approve: (() -> Void)? = nil, dismiss: @escaping () -> Void
    ) {
        self.name = name
        self.agents = agents
        self.filed = filed
        self.from = from
        self.asked = asked
        self.waiting = waiting
        self.openSession = openSession
        self.askForChanges = askForChanges
        self.approve = approve
        self.dismiss = dismiss
    }

    package var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(agents) { row($0) }
        }
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            if let name {
                // Capped: until a milestone is filed the name is what was typed, which can run long
                // enough to push out where the request has got to.
                Text(name).font(Typography.body(.semibold)).foregroundStyle(Theme.tx).lineLimit(1)
                    .frame(maxWidth: 340, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            }
            Text(RequestBanner.line(of: filed, finished: approve != nil, from: from, asked: asked, waiting: waiting))
                .font(Typography.body).foregroundStyle(name == nil ? Theme.tx : Theme.tx2).lineLimit(1)
            Spacer(minLength: 12)
            // Each agent's row opens its own session; with none listed, this is the way there.
            if let openSession, agents.isEmpty {
                Button("Open session", action: openSession).buttonStyle(.consoleGhost)
            }
            if !filed.isEmpty || approve != nil {
                Button("Ask for changes", action: askForChanges).buttonStyle(.console)
            }
            if let approve {
                Button(action: approve) { Label("Approve and commit", systemImage: "checkmark.seal") }
                    .buttonStyle(.consolePrimary)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.tx3)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// One agent: who and where, what it is doing, what it has filed, and the way to its session.
    /// The asked project's Product sits under the one that asked it.
    private func row(_ agent: Agent) -> some View {
        HStack(spacing: 12) {
            AgentStateGlyph(state: agent.state, size: 11)
            HStack(spacing: 7) {
                if agent.asked { Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold)) }
                Text(agent.name).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                NotebookStyle.chip(agent.project, mono: true)
            }
            .padding(.leading, agent.asked ? 12 : 0)
            .foregroundStyle(Theme.tx3)
            .frame(width: 260, alignment: .leading)
            Text(agent.doing).font(Typography.body)
                .foregroundStyle(agent.state == .working ? Theme.tx2 : agent.state.color).lineLimit(1)
            Spacer(minLength: 12)
            Text(agent.filed).font(Typography.caption).foregroundStyle(Theme.tx2).lineLimit(1)
            Group {
                if let open = agent.open { Button("Open session", action: open).buttonStyle(.consoleGhost) }
            }
            .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// What the banner says, with the other project's name, if any, in bold. Waiting on that
    /// project's answer is all there is to say until it comes: what Product asked, dimmed after it.
    static func line(
        of filed: [NotebookCard], finished: Bool, from: String? = nil, asked: (project: String, title: String)? = nil,
        waiting: Bool = false
    ) -> AttributedString {
        if let asked, waiting {
            var title = AttributedString(" · asked “\(asked.title)”")
            title.foregroundColor = Theme.tx3
            return naming(asked.project, in: "Product is waiting on \(asked.project)’s answer") + title
        }
        if let from { return naming(from, in: summary(of: filed, finished: finished, whose: "\(from)’s")) }
        let own = summary(of: filed, finished: finished)
        guard let asked else { return AttributedString(own) }
        return naming(asked.project, in: String(own.dropLast()) + "; \(asked.project) filed its own part.")
    }

    /// `sentence`, with the first `name` in it set in bold.
    private static func naming(_ name: String, in sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: name) { text[range].font = Typography.body(.semibold) }
        return text
    }

    /// "a milestone and 3 tasks", in the board's own words for them.
    /// `finished` with nothing new filed is a request Product answered by changing what was there.
    static func summary(of filed: [NotebookCard], finished: Bool = false, whose: String = "your") -> String {
        guard let counted = counted(filed) else {
            return finished ? "Product changed the board for \(whose) request." : "Product is on \(whose) request."
        }
        return "Product filed \(whose) request as " + counted + "."
    }

    /// "a milestone and 3 tasks", or nil with nothing filed.
    package static func counted(_ filed: [NotebookCard]) -> String? {
        let counted = [
            count(filed.filter { $0.kind == .project }.count, "milestone"),
            count(filed.filter { $0.kind == .task }.count, "task"),
        ].compactMap { $0 }
        return counted.isEmpty ? nil : counted.joined(separator: " and ")
    }

    private static func count(_ number: Int, _ noun: String) -> String? {
        switch number {
        case 0: return nil
        case 1: return "a \(noun)"
        default: return "\(number) \(noun)s"
        }
    }
}
