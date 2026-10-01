import SwiftUI

/// What the board shows with no chains to draw: the roadmap the work will serve, why there is
/// no work yet, and what to ask Product for.
extension NotebookBoard {
    var empty: some View {
        VStack(spacing: 0) {
            // The goal is still worth reading with nothing under it — it is what Product plans from.
            if !roadmaps.isEmpty {
                VStack(spacing: 18) {
                    ForEach(roadmaps) { roadmap in RoadmapBand(roadmap: roadmap, cards: cards) { openCard(roadmap) } }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
            }
            prompt.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGrid())
    }

    private var prompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash").font(.system(size: 22))
                .foregroundStyle(Theme.tx4)
            Text(
                cards.contains { $0.kind == .task }
                    ? "Every task here is done."
                    : "No tasks yet — Product writes them."
            )
            .font(Typography.body).foregroundStyle(Theme.tx3)
            // The bar's two ways to ask Product, again where an empty board puts your eye.
            HStack(spacing: 8) {
                Button {
                    review()
                } label: {
                    Label("Product review", systemImage: "sparkles")
                }
                if let request {
                    Button {
                        request()
                    } label: {
                        Label("New request", systemImage: "text.bubble")
                    }
                }
            }
            .buttonStyle(.console)
        }
    }
}
