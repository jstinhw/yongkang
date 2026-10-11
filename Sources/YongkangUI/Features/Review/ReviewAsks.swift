import SwiftUI
import YongkangCore

/// What the agent left for a person, above everything it did: its questions, each answered in a
/// click and sent back to it, then the few places it says only a person should read — what no
/// check covers — each unfolding its own lines of the diff, where a line can be commented on.
struct ReviewAsks: View {
    let review: WorkReview
    /// The diffs of the task's files, read when the page opened; empty until then.
    let diffs: [String: [DiffLine]]
    let loading: Bool
    @Binding var draft: ReviewDraft
    /// What was sent for a question, or nil before anything was.
    let answered: (String) -> String?
    let answer: (_ question: String, _ answer: String) -> Void
    let openFile: (String) -> Void

    /// The spot unfolded, none to begin with: the page opens on why to look, and the code is
    /// one click away.
    @State private var open: Int?
    @State private var typed: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Needs you")
            ForEach(Array((review.questions ?? []).enumerated()), id: \.offset) { _, question in
                questionRow(question)
            }
            if let spots = review.spots, !spots.isEmpty {
                Text(
                    "Read \(spots.count == 1 ? "this spot" : "these \(spots.count) spots") — the checks below cover the rest."
                )
                .font(Typography.body).foregroundStyle(Theme.tx2)
                ForEach(Array(spots.enumerated()), id: \.offset) { index, spot in spotRow(spot, index) }
            }
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

    // MARK: - Spots

    /// The path and the reason are text to select, so only the chevron unfolds the excerpt.
    private func spotRow(_ spot: WorkReview.Spot, _ index: Int) -> some View {
        let unfolded = open == index
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                Text("\(index + 1)").font(Typography.caption(.bold)).foregroundStyle(Theme.amber)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.amber.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(spot.path).font(Typography.code(.semibold)).foregroundStyle(Theme.tx)
                            .lineLimit(1).truncationMode(.head)
                            .textSelection(.enabled)
                        Text(place(spot)).font(Typography.mono).foregroundStyle(Theme.tx2)
                            .textSelection(.enabled)
                    }
                    Text(spot.why).font(Typography.body).foregroundStyle(Theme.prose)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button {
                    open = unfolded ? nil : index
                } label: {
                    Image(systemName: unfolded ? "chevron.down" : "chevron.right")
                        .font(Typography.caption(.semibold)).foregroundStyle(Theme.tx3)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(unfolded ? "Hide the lines" : "Show the lines")
                .accessibilityLabel("Spot \(index + 1), \(spot.path), \(unfolded ? "unfolded" : "folded")")
            }
            .padding(12)
            if unfolded { excerpt(spot) }
        }
        .background(Theme.well)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.wellLine, lineWidth: 1))
    }

    private func place(_ spot: WorkReview.Spot) -> String {
        let lines = spot.range.map { $0.count == 1 ? "L\($0.lowerBound)" : "L\($0.lowerBound)–\($0.upperBound)" }
        return [spot.label, lines].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func excerpt(_ spot: WorkReview.Spot) -> some View {
        let lines = spot.excerpt(of: diffs[spot.path] ?? [])
        VStack(alignment: .leading, spacing: 6) {
            if !lines.isEmpty {
                ScrollView(.horizontal) { DiffLines(path: spot.path, lines: lines, draft: $draft) }
            } else {
                Text(loading ? "Reading the diff…" : "These lines are not in this task’s diff.")
                    .font(Typography.body).foregroundStyle(Theme.tx3).padding(.horizontal, 12)
            }
            Button("Open the whole diff") { openFile(spot.path) }
                .buttonStyle(.plain).font(Typography.body).foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
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
