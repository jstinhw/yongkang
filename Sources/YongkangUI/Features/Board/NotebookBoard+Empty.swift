import SwiftUI

/// What the board shows with no chains to draw: why it is empty, and the one thing to do about it.
extension NotebookBoard {
    @ViewBuilder var empty: some View {
        switch setup {
        case .running(let open)?:
            settingUp(ProgressView().controlSize(.small), "Notebook Setup is writing this project’s notebook.") {
                Button(action: open) { Label("Open Notebook Setup", systemImage: "terminal") }
            }
        case .stopped(let rerun)?:
            settingUp(
                Image(systemName: "book.closed").font(.system(size: 22)).foregroundStyle(Theme.tx4),
                "No notebook yet — Notebook Setup reads the project and writes one."
            ) {
                Button(action: rerun) { Label("Run Notebook Setup", systemImage: "arrow.clockwise") }
            }
        case nil:
            noTasks
        }
    }

    /// The same place and size as `noTasks`, so the board does not jump when the first tasks land.
    private func settingUp(
        _ icon: some View, _ text: String, @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(spacing: 10) {
            icon.frame(height: 26)
            Text(text).font(Typography.body).foregroundStyle(Theme.tx3)
            action().buttonStyle(.console)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGrid())
    }

    private var noTasks: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGrid())
    }
}
