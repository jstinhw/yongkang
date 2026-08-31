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
                .font(.title2.weight(.semibold))
            Text("""
                 Describe the project: the goal, what you are building and for whom, the \
                 features, the constraints, what is out of scope. The agent fills the gaps \
                 with a few multiple-choice questions, then writes the notebook without \
                 waiting for approval — read it on the board and tell it what to change.
                 """)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("This project is…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...14)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .focused($focused)
                .onSubmit(send)

            HStack {
                Text("Return to start · Shift-Return for a new line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // ponytail: Return reaches send() either through the field's onSubmit or,
                // if the field swallows it, through this default button. send() is
                // guarded so both firing still starts one session.
                Button("Start Session", action: send)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { focused = true }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        guard !sent, !trimmed.isEmpty else { return }
        sent = true
        start(trimmed)
    }
}
