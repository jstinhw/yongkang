import SwiftUI

/// What an empty project shows instead of a blank pane: say what the project is,
/// press Return, and that text opens the session that writes the notebook.
struct ProjectIntake: View {
    let project: Project
    let start: (String) -> Void

    @State private var text = ""
    @State private var sent = false

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

            PromptField(placeholder: "This project is…", root: project.directory,
                        text: $text, submit: send)

            HStack {
                Text("@ tags a file or folder · Tab completes it · Return to start")
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
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        if Mention.accept(&text, root: project.directory, absolute: false) { return }
        guard !sent, !trimmed.isEmpty else { return }
        sent = true
        start(trimmed)
    }
}
