import SwiftUI
import YongkangCore

/// What the agent left for a person to decide, above everything it did: its questions, each
/// answered in a click and sent back to it. Only what waits on an answer is here; code to read
/// is `ReviewSpots`, further down, because reading is never what holds the work up.
struct ReviewAsks: View {
    let questions: [WorkReview.Question]
    /// What was sent for a question, or nil before anything was.
    let answered: (String) -> String?
    let answer: (_ question: String, _ answer: String) -> Void

    @State private var typed: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Needs you")
            ForEach(Array(questions.enumerated()), id: \.offset) { _, question in questionRow(question) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15, border: Theme.amber.opacity(0.32))
    }

    // MARK: - Questions

    private func questionRow(_ question: WorkReview.Question) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle").font(Typography.headline).foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.ask).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let context = question.context {
                        Text(context).font(Typography.body).foregroundStyle(Theme.tx2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                if let sent = answered(question.ask) {
                    Label("Sent: “\(sent)”", systemImage: "checkmark")
                        .font(Typography.body).foregroundStyle(Theme.green)
                } else {
                    choices(question)
                }
            }
            Spacer(minLength: 0)
        }
        .cardSurface(radius: 10, padding: 12, border: Theme.wellLine, fill: Theme.well)
    }

    private func choices(_ question: WorkReview.Question) -> some View {
        let options = question.options ?? []
        return VStack(alignment: .leading, spacing: 8) {
            if !options.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button(option) { answer(question.ask, option) }
                            .buttonStyle(ReviewChoiceStyle(primary: index == question.recommend))
                    }
                }
                if let pick = question.recommend, options.indices.contains(pick) {
                    Text("The agent would pick “\(options[pick])”.").font(Typography.caption).foregroundStyle(Theme.tx2)
                }
            }
            TextField(
                options.isEmpty ? "Answer the agent" : "Or answer in your words",
                text: Binding {
                    typed[question.ask] ?? ""
                } set: {
                    typed[question.ask] = $0
                }
            )
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Theme.tx)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line2, lineWidth: 1))
            .onSubmit {
                let said = (typed[question.ask] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !said.isEmpty else { return }
                answer(question.ask, said)
            }
        }
    }
}

/// An answer to an agent's question: the one it recommends filled, the rest outlined.
private struct ReviewChoiceStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body(.semibold))
            .foregroundStyle(primary ? Theme.bg : Theme.tx)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(primary ? Theme.accent : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(primary ? Theme.accent : Theme.controlLine))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
