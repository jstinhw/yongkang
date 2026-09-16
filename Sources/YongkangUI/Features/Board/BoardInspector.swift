import SwiftUI
import YongkangCore

/// The board's right-hand column: what is waiting on you, what you have picked, and what
/// the console will do with it. The batch used to be crammed into the action bar as a run
/// of ids; here it has room to say which of them are design tasks, which is the
/// difference between "an engineer starts on this" and "you see it first".
struct BoardInspector: View {
    /// Demos still waiting on the user, in board order.
    let demos: [UserBlock]
    let cards: [NotebookCard]
    /// The picks plus the unfinished work they pull in, in build order.
    let batch: [NotebookCard]
    /// Which of the batch the user actually clicked, as opposed to what came along.
    let picked: Set<String>
    let openDemo: (UserBlock) -> Void
    /// Folded into the board itself when the window is too narrow to carry a fourth
    /// column — the same move the lead's board makes.
    var inline = false

    private var designCount: Int { batch.filter(\.isDesignWork).count }

    var body: some View {
        if inline {
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Inspector { content }
        }
    }

    @ViewBuilder private var content: some View {
        if !demos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Waiting on you", trailing: "\(demos.count)")
                ForEach(demos) { demo in waiting(demo) }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("The batch", trailing: batch.isEmpty ? nil : "\(batch.count)")
            if batch.isEmpty {
                Text("Click a task to pick it. Anything it waits on comes along.")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(batch.enumerated()), id: \.element.id) { index, card in
                    row(index: index, card: card)
                }
            }
        }

        if !batch.isEmpty { design }
        if !inline { Spacer(minLength: 0) }
    }

    private func waiting(_ demo: UserBlock) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                StateDot(color: Theme.amber, live: true)
                Text("demo ready").font(Typo.text(11, .medium)).foregroundStyle(Theme.amber)
                Spacer(minLength: 0)
                if let task = demo.task {
                    Text(task).font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
                }
            }
            Text(demo.title).font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Button {
                openDemo(demo)
            } label: {
                Text("Open demo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.consolePrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 13, border: Theme.amber.opacity(0.32))
    }

    private func row(index: Int, card: NotebookCard) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(Typography.mono).foregroundStyle(Theme.tx3)
                .frame(width: 14, alignment: .leading)
            Text(card.id).font(Typo.mono(11)).foregroundStyle(Theme.tx).lineLimit(1)
            Spacer(minLength: 4)
            if card.isDesignWork {
                Text("design first").font(Typography.caption).foregroundStyle(Theme.violet)
            } else {
                Text(picked.contains(card.id) ? "picked" : "pulled in")
                    .font(Typography.caption)
                    .foregroundStyle(picked.contains(card.id) ? Theme.tx2 : Theme.tx3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line2, lineWidth: 1))
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
                    ? "\(designCount) of these are design tasks. A designer builds each one onto the same demo, and you approve it, before the engineering tasks waiting on it can start."
                    : "No design tasks in this batch, so it goes straight to the lead."
            )
            .font(Typography.body).foregroundStyle(Theme.tx2)
            .fixedSize(horizontal: false, vertical: true)
            if designCount > 0 {
                VStack(alignment: .leading, spacing: 9) {
                    step(
                        1, "Product writes design as its own task, and the engineering tasks on that screen wait on it."
                    )
                    step(
                        2,
                        "The designer builds it onto the project's demo — one change at a time, so you review one at a time."
                    )
                    step(3, "You approve it, or say what to change. Only then do the engineers start.")
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
