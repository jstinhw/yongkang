import SwiftUI
import YongkangCore

/// What is being asked of the user, and the button that goes to the engineer doing it. Only
/// the user's half of the body is drawn — `UserBlock.brief`; the walking-through happens in
/// that engineer's session, a step at a time, with the page it needs beside it.
/// The action bar either opens the guiding session or returns a proposal to Product.
///
/// A proposal shows the page its session drew instead of its own body. The body is the
/// draft — every task, every `depends_on`, every call made — which is too long to decide
/// on; the page is that plan as outcomes, what waits on the user, and a graph.
package struct BlockDetail: View {
    let block: UserBlock
    let cards: [NotebookCard]
    /// The session that is waiting on this, if it is still running.
    let waiting: CodeSession?
    /// Where the session's page is looked for. Nil in the shots, which draw the body.
    let notebookRoot: URL?
    let start: () -> Void
    let revise: () -> Void
    let resolve: () -> Void

    @State private var content: [NotebookContent.Section] = []

    package init(
        block: UserBlock,
        cards: [NotebookCard],
        waiting: CodeSession?,
        notebookRoot: URL? = nil,
        start: @escaping () -> Void,
        revise: @escaping () -> Void,
        resolve: @escaping () -> Void
    ) {
        self.block = block
        self.cards = cards
        self.waiting = waiting
        self.notebookRoot = notebookRoot
        self.start = start
        self.revise = revise
        self.resolve = resolve
    }

    /// The page its session drew, when a proposal has one. A proposal outlives the session
    /// that wrote it — setup closes as soon as the draft is done — so this is the only place
    /// the graph is still reachable.
    private var page: (session: UUID, notebookRoot: URL)? {
        guard block.isProposal, let session = block.session, let notebookRoot,
            NotebookFormat.drawnPage(of: session, in: notebookRoot) != nil
        else { return nil }
        return (session, notebookRoot)
    }

    private var parent: NotebookCard? {
        block.task.flatMap { id in cards.first { $0.id == id } }
    }

    package var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // The page scrolls itself, so the header sits in its own band above it rather
                // than inside a scroll view wrapping both.
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
                    if let page {
                        SessionPage(session: page.session, notebookRoot: page.notebookRoot)
                    } else if !content.isEmpty {
                        ScrollView {
                            NotebookContentView(sections: content, cards: cards)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardSurface(padding: 16)
                                .padding([.horizontal, .bottom], 24)
                        }
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                inspector
            }
            actionBar
        }
        .background(Theme.bg)
        .task(id: block.brief) { load() }
    }

    private var tint: Color {
        block.waiting ? (block.isProposal ? Theme.violet : Theme.amber) : Theme.green
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(
                    systemName: block.waiting
                        ? (block.isProposal ? "lightbulb.fill" : "hand.raised.fill")
                        : "checkmark.circle.fill"
                )
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11).fill(tint.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(tint.opacity(0.3), lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.title).font(Typography.title)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        NotebookStyle.pill(
                            block.waiting
                                ? (block.isProposal
                                    ? (block.proposalReady ? "ready to create" : "needs your input")
                                    : "waiting on you")
                                : "done", tint)
                        Text(subtitle).font(Typography.body).foregroundStyle(Theme.tx3)
                    }
                }
                Spacer(minLength: 12)
            }
            if !block.resolution.isEmpty {
                Text(block.resolution).font(Typography.body).foregroundStyle(Theme.prose)
            }
        }
    }

    private var subtitle: String {
        if block.isProposal {
            let lead =
                !block.waiting
                ? "Built out"
                : block.proposalReady ? "Product plan is ready" : "Product is waiting in its transcript"
            return parent.map { "\(lead) — advances \($0.title)" } ?? lead
        }
        let who = waiting.map { "\($0.title) is waiting" } ?? "Nothing is waiting on it any more"
        return parent.map { "\(who) — holds up \($0.title)" } ?? who
    }

    // MARK: - Inspector

    private var inspector: some View {
        Inspector {
            if let parent {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(block.isProposal ? "Advances" : "Holds up")
                    HStack(spacing: 10) {
                        NotebookStyle.statusRing(parent.status, progress: 0, size: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parent.title).font(Typography.body).foregroundStyle(Theme.tx)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(parent.id).font(Typography.mono).foregroundStyle(Theme.tx3)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(padding: 15)
            }

            if let waiting {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Waiting agent")
                    HStack(spacing: 10) {
                        RoleTile(role: waiting.holdsTasks ? "work" : waiting.title)
                        Text(waiting.title).font(Typography.body).foregroundStyle(Theme.tx2).lineLimit(1)
                        Spacer(minLength: 0)
                        NotebookStyle.pill("blocked", Theme.amber)
                    }
                }
            }

            if let link = block.link {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("The page you need")
                    Link(destination: link) {
                        HStack(spacing: 9) {
                            Image(systemName: "link").font(.system(size: 12))
                                .foregroundStyle(Theme.accent)
                            Text(link.absoluteString).font(Typography.mono)
                                .foregroundStyle(Theme.accent).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.well))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Theme.wellLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            if !block.isProposal {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "lock.shield").font(.system(size: 12)).foregroundStyle(Theme.red)
                    Text("No secret is ever echoed back to you or written into the notebook.")
                        .font(Typography.caption).foregroundStyle(Theme.problem)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.red.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.red.opacity(0.18), lineWidth: 1))
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        ActionBar {
            Text(footer).font(Typography.body).foregroundStyle(Theme.tx3).lineLimit(1)
            Spacer(minLength: 12)
            if block.waiting {
                if block.isProposal && block.proposalReady {
                    Button("Request changes", action: revise).buttonStyle(.console)
                    Button(action: start) {
                        Label("Create project", systemImage: "checkmark")
                    }
                    .buttonStyle(.consolePrimary)
                } else if block.isProposal {
                    Button(action: revise) {
                        Label("Open Product session", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.consolePrimary)
                } else {
                    Button("Mark resolved", action: resolve).buttonStyle(.console)
                    Button(action: start) { Label("Do it now", systemImage: "bolt.fill") }
                        .buttonStyle(.consolePrimary)
                }
            }
        }
    }

    private var footer: String {
        guard block.waiting else { return "Cleared." }
        guard block.isProposal else {
            return "An engineer explains this first, then walks you through it one step at a time."
        }
        return block.proposalReady
            ? "Request changes in Product, or create the reviewed milestone and tasks."
            : "Review and refine this with Product in the original transcript."
    }

    private func load() {
        content = NotebookContent.sections(block.brief)
    }
}
