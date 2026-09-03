import SwiftUI

/// What is being asked of the user, and the button that starts doing it. The body of a
/// block is written as steps by whoever hit the gate, so it renders like any other page —
/// what makes this screen different is the bar: it starts a session whose whole job is
/// walking you through this one thing and then releasing the agent that is waiting.
struct BlockDetail: View {
    let block: UserBlock
    let cards: [NotebookCard]
    /// The session that is waiting on this, if it is still running.
    let waiting: CodeSession?
    let start: () -> Void
    let revise: () -> Void
    let resolve: () -> Void

    @State private var content: [NotebookContent.Section] = []

    private var parent: NotebookCard? {
        block.task.flatMap { id in cards.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if !content.isEmpty {
                            NotebookContentView(sections: content, cards: cards)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardSurface(padding: 16)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                inspector
            }
            actionBar
        }
        .background(Theme.bg)
        .task(id: block.id) { load() }
    }

    private var tint: Color {
        block.waiting ? (block.isProposal ? Theme.violet : Theme.amber) : Theme.green
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: block.waiting
                      ? (block.isProposal ? "lightbulb.fill" : "hand.raised.fill")
                      : "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11).fill(tint.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(tint.opacity(0.3), lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.title).font(Typo.display(21))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        NotebookStyle.pill(block.waiting
                                           ? (block.isProposal
                                              ? (block.proposalReady ? "ready to create" : "needs your input")
                                              : "waiting on you")
                                           : "done", tint)
                        Text(subtitle).font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                    }
                }
                Spacer(minLength: 12)
            }
            if !block.resolution.isEmpty {
                Text(block.resolution).font(Typo.text(12.5)).foregroundStyle(Color(hex: 0xC7D0DC))
            }
        }
    }

    private var subtitle: String {
        if block.isProposal {
            let lead = !block.waiting ? "Built out"
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
                    SectionLabel("Holds up")
                    HStack(spacing: 10) {
                        NotebookStyle.statusRing(parent.status, progress: 0, size: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parent.title).font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(parent.id).font(Typo.mono(10)).foregroundStyle(Theme.tx3)
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
                        RoleTile(role: waiting.isEngineeringLead ? "lead" : waiting.title)
                        Text(waiting.title).font(Typo.text(12)).foregroundStyle(Theme.tx2).lineLimit(1)
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
                            Text(link.absoluteString).font(Typo.mono(10.5))
                                .foregroundStyle(Theme.accent).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x12161E)))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color(hex: 0x1E242F), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            if !block.isProposal {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "lock.shield").font(.system(size: 12)).foregroundStyle(Theme.red)
                    Text("No secret is ever echoed back to you or written into the notebook.")
                        .font(Typo.text(11)).foregroundStyle(Color(hex: 0xF1BDBD))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.red.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.red.opacity(0.18), lineWidth: 1))
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        ActionBar {
            Text(footer).font(Typo.text(12)).foregroundStyle(Theme.tx3).lineLimit(1)
            Spacer(minLength: 12)
            if block.isProposal && block.proposalReady {
                Button("Request changes", action: revise).buttonStyle(.console)
                Button(action: start) {
                    Label("Create project", systemImage: "checkmark")
                }
                .buttonStyle(.consolePrimary)
                .disabled(!block.waiting)
            } else {
                Button(block.isProposal ? "Dismiss" : "Mark resolved", action: resolve)
                    .buttonStyle(.console)
                    .disabled(!block.waiting)
                Button(action: block.isProposal ? revise : start) {
                    Label(block.isProposal ? "Open Product session" : "Do it now",
                          systemImage: block.isProposal ? "bubble.left.and.bubble.right" : "bolt.fill")
                }
                .buttonStyle(.consolePrimary)
                .disabled(!block.waiting)
            }
        }
    }

    private var footer: String {
        guard block.waiting else { return "Cleared." }
        guard block.isProposal else {
            return "An engineer explains this first, then walks you through it one step at a time."
        }
        return block.proposalReady
            ? "Request changes in Product, or create the reviewed project and tasks."
            : "Review and refine this with Product in the original transcript."
    }

    private func load() {
        let text = (try? String(contentsOf: block.url, encoding: .utf8)) ?? ""
        content = NotebookContent.sections(NotebookIndex.body(text))
    }
}
