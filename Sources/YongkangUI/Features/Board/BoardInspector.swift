import SwiftUI
import YongkangCore

/// The board's right-hand column: what is waiting on you, and what the console will do with
/// what you have picked. The picks themselves are the board — the cards are lit there, and
/// the action bar counts them — so this column only says which of them are design tasks,
/// which is the difference between "an engineer starts on this" and "you see it first".
struct BoardInspector: View {
    /// Everything waiting on the user — demos, gates and proposals alike, so this column
    /// and the sidebar's "Waiting on you" are the same list.
    let waiting: [UserBlock]
    /// The picks plus the unfinished work they pull in, in build order.
    let batch: [NotebookCard]
    let openBlock: (UserBlock) -> Void

    private var designCount: Int { batch.filter(\.isDesignWork).count }

    var body: some View {
        Inspector { content }
    }

    @ViewBuilder private var content: some View {
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Waiting on you", trailing: "\(waiting.count)")
                ForEach(waiting) { block in card(block) }
            }
        }

        if !batch.isEmpty { design }
        Spacer(minLength: 0)
    }

    /// One thing on the user's desk. A demo, a gate and a proposal are the same card — what
    /// differs is the word at the top and what the button opens.
    private func card(_ block: UserBlock) -> some View {
        let tint = block.isProposal ? Theme.violet : Theme.amber
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                StateDot(color: tint, live: true)
                Text(BoardInspector.state(block)).font(Typography.caption(.medium))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                if let task = block.task {
                    Text(task).font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
                }
            }
            Text(block.title).font(Typography.body).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Button {
                openBlock(block)
            } label: {
                Text(BoardInspector.open(block)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.consolePrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 13, border: tint.opacity(0.32))
    }

    /// The three wordings a block gets on the board, in one place because the column and the
    /// task card both say them.
    static func state(_ block: UserBlock) -> String {
        if block.isDemo { return "demo ready" }
        return block.isProposal ? (block.proposalReady ? "ready to create" : "needs you") : "blocked"
    }

    static func open(_ block: UserBlock) -> String {
        if block.isDemo { return "Open demo" }
        return block.isProposal ? "Open proposal" : "Open block"
    }

    /// What a block says when whoever filed it left `action` empty.
    static func fallbackAction(_ block: UserBlock) -> String {
        block.isDemo
            ? "A demo is waiting. Nothing that depends on it starts until you have looked at it."
            : "An agent is stopped here until you settle this."
    }

    /// What the console is about to do with the batch, spelled out before the button is
    /// pressed rather than discovered afterwards.
    private var design: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                SectionLabel("Design work")
                RoleTile(role: "design", size: 20)
                Spacer(minLength: 0)
            }
            Text(
                designCount > 0
                    ? "\(designCount) of these are design tasks. A designer builds each one onto the same demo, and you approve it, before the tasks waiting on it can start."
                    : "No design tasks in this batch, so it goes straight to the agent."
            )
            .font(Typography.body).foregroundStyle(Theme.tx2)
            .fixedSize(horizontal: false, vertical: true)
            if designCount > 0 {
                VStack(alignment: .leading, spacing: 9) {
                    step(
                        1, "Product writes design as its own task, and the tasks that build that screen wait on it."
                    )
                    step(
                        2,
                        "The designer builds it onto the project's demo — one change at a time, so you review one at a time."
                    )
                    step(3, "You approve it, or say what to change. Only then does the work on that screen start.")
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)").font(Typography.mono).foregroundStyle(Theme.violet).padding(.top, 1)
            Text(text).font(Typography.body).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
