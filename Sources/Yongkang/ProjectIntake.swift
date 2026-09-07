import SwiftUI

/// What an empty project shows instead of a blank pane: say what the project is,
/// press Return, and that text opens the session that writes the notebook.
struct ProjectIntake: View {
    let project: Project
    let start: (String) -> Void

    @State private var text = ""
    @State private var sent = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Text("What is \(project.name) for?")
                .font(Typo.display(24))
            Text("""
                 Describe the project: the goal, what you are building and for whom, the \
                 features, the constraints, what is out of scope. The agent fills the gaps \
                 with a few multiple-choice questions, then writes the notebook without \
                 waiting for approval — read it on the board and tell it what to change.
                 """)
                .font(Typo.text(13))
                .foregroundStyle(Theme.tx2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            TextField("This project is…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...14)
                .font(Typo.text(13))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line2, lineWidth: 1))
                .focused($focused)
                .onSubmit(send)

            HStack {
                Text("Return to start · Shift-Return for a new line")
                    .font(Typo.mono(10.5))
                    .foregroundStyle(Theme.tx3)
                Spacer()
                // ponytail: Return reaches send() either through the field's onSubmit or,
                // if the field swallows it, through this default button. send() is
                // guarded so both firing still starts one session.
                Button("Start session", action: send)
                    .buttonStyle(.consolePrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task { focused = true }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        guard !sent, !trimmed.isEmpty else { return }
        sent = true
        start(trimmed)
    }
}
