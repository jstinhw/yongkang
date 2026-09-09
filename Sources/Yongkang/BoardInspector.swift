import SwiftUI

/// The board's right-hand column: what is waiting on you, what you have picked, and what
/// the console will do with it. The batch used to be crammed into the action bar as a run
/// of ids; here it has room to say which of them Product marked as design work, which is
/// the difference between "an engineer starts on this" and "you see it first".
struct BoardInspector: View {
    /// Demos still waiting on the user, in board order.
    let demos: [UserBlock]
    let cards: [NotebookCard]
    /// The picks plus the unfinished work they pull in, in build order.
    let batch: [NotebookCard]
    /// Which of the batch the user actually clicked, as opposed to what came along.
    let picked: Set<String>
    let openDemo: (UserBlock) -> Void

    private var designCount: Int { batch.filter(\.isDesignWork).count }

    var body: some View {
        Inspector {
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
                        .font(Typo.text(12)).foregroundStyle(Theme.tx3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(batch.enumerated()), id: \.element.id) { index, card in
                        row(index: index, card: card)
                    }
                }
            }

            if !batch.isEmpty { design }
            Spacer(minLength: 0)
        }
    }

    private func waiting(_ demo: UserBlock) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                StateDot(color: Theme.amber, live: true)
                Text("demo ready").font(Typo.text(11, .medium)).foregroundStyle(Theme.amber)
                Spacer(minLength: 0)
                if let task = demo.task {
                    Text(task).font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(1)
                }
            }
            Text(demo.title).font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Button { openDemo(demo) } label: {
                Text("Open demo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.consolePrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 13, border: Theme.amber.opacity(0.32))
    }

    private func row(index: Int, card: NotebookCard) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                .frame(width: 14, alignment: .leading)
            Text(card.id).font(Typo.mono(11)).foregroundStyle(Theme.tx).lineLimit(1)
            Spacer(minLength: 4)
            if card.isDesignWork {
                Text("design first").font(Typo.text(10.5)).foregroundStyle(Theme.violet)
            } else {
                Text(picked.contains(card.id) ? "picked" : "pulled in")
                    .font(Typo.text(10.5))
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
            Text(designCount > 0
                 ? "Product marked \(designCount) of these as design work. A designer builds each one as a demo, and you approve it, before an engineer touches the repo."
                 : "Product marked none of these as design work, so the batch goes straight to the lead.")
                .font(Typo.text(12)).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
            if designCount > 0 {
                VStack(alignment: .leading, spacing: 9) {
                    step(1, "Product decides a task is design work and puts a designer on it.")
                    step(2, "The designer builds the demo first. You can follow it while they work.")
                    step(3, "You approve it. Only then does the lead give it to engineers.")
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)").font(Typo.mono(10)).foregroundStyle(Theme.violet).padding(.top, 1)
            Text(text).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
