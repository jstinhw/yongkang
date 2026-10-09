import SwiftUI
import YongkangCore

/// The four answers a review is read for in ten seconds, side by side under the title: how sure
/// the agent is, what it ran, what the work reaches, and what is left for the reviewer. Each is
/// one big line and one small one; everything behind them is further down the page.
///
/// What it reaches is git's answer — the files, their lines and their areas — with the agent's
/// own words for it on top, so the one tile it could get wrong has the numbers beside it.
struct ReviewGlance: View {
    let review: WorkReview
    let task: SummaryTask
    let areas: [ReviewArea]
    /// Open blocks, unanswered questions and spots: everything under Needs you.
    let blocks: Int
    let questions: Int

    private var checks: [WorkReview.Check] { review.checks ?? [] }

    var body: some View {
        // Four across when they fit, two by two when they don't; a Grid, so every tile in a row
        // is as tall as its tallest.
        ViewThatFits(in: .horizontal) {
            grid(columns: 4).frame(minWidth: 680)
            grid(columns: 2)
        }
    }

    private func grid(columns: Int) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: 4, by: columns)), id: \.self) { first in
                GridRow {
                    ForEach(first..<first + columns, id: \.self) { tile(at: $0) }
                }
            }
        }
    }

    @ViewBuilder private func tile(at index: Int) -> some View {
        switch index {
        case 0: confidence
        case 1: checked
        case 2: touches
        default: needsYou
        }
    }

    private var confidence: some View {
        tile("Agent’s confidence", border: review.confidence.tint.opacity(0.32)) {
            HStack(spacing: 10) {
                Text(review.confidence.label).font(Typography.headline).foregroundStyle(review.confidence.tint)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { step in
                        Capsule()
                            .fill(step < review.confidence.steps ? review.confidence.tint : Theme.wellLine)
                            .frame(width: 16, height: 5)
                    }
                }
                .accessibilityHidden(true)
            }
        } detail: {
            review.confidenceWhy ?? ""
        }
    }

    private var checked: some View {
        tile("Checks it ran") {
            HStack(spacing: 10) {
                Text(checks.isEmpty ? "None" : "\(count(.passed)) of \(checks.count) passed")
                    .font(Typography.headline).foregroundStyle(checks.isEmpty ? Theme.amber : Theme.tx)
                HStack(spacing: 3) {
                    ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                        Circle().fill(check.status.tint).frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
        } detail: {
            checks.isEmpty
                ? "Nothing but you has checked it."
                : [
                    count(.failed) > 0 ? "\(count(.failed)) failed" : "",
                    count(.notRun) > 0 ? "\(count(.notRun)) could not run here" : "",
                ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private var touches: some View {
        tile("What it touches") {
            Text(review.touches ?? areas.map(\.rawValue).joined(separator: ", "))
                .font(Typography.headline).foregroundStyle(Theme.tx)
                .fixedSize(horizontal: false, vertical: true)
        } detail: {
            "\(task.files.count) file\(task.files.count == 1 ? "" : "s") · +\(task.added) −\(task.removed)"
                + (areas.isEmpty || review.touches == nil ? "" : " · " + areas.map(\.rawValue).joined(separator: ", "))
        }
    }

    private var needsYou: some View {
        tile("Needs you", tint: asks > 0 ? Theme.amber : Theme.tx2, border: asks > 0 ? Theme.amber.opacity(0.32) : nil)
        {
            Text(asks > 0 ? needs : "Nothing").font(Typography.headline).foregroundStyle(Theme.tx)
        } detail: {
            asks > 0 ? "Below, before anything else" : "Approve when the checks satisfy you"
        }
    }

    private var spots: Int { review.spots?.count ?? 0 }
    private var asks: Int { blocks + questions + spots }

    private var needs: String {
        [
            blocks > 0 ? "\(blocks) block\(blocks == 1 ? "" : "s")" : "",
            questions > 0 ? "\(questions) question\(questions == 1 ? "" : "s")" : "",
            spots > 0 ? "\(spots) spot\(spots == 1 ? "" : "s")" : "",
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func count(_ status: WorkReview.Check.Status) -> Int { checks.filter { $0.status == status }.count }

    private func tile<Value: View>(
        _ label: String, tint: Color = Theme.tx2, border: Color? = nil,
        @ViewBuilder value: () -> Value, detail: () -> String
    ) -> some View {
        let said = detail()
        return VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Typography.section).tracking(1.4).foregroundStyle(tint)
            value()
            if !said.isEmpty {
                Text(said).font(Typography.body).foregroundStyle(Theme.prose)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(padding: 13, border: border ?? Theme.line2)
        .accessibilityElement(children: .combine)
    }
}

extension WorkReview.Confidence {
    var tint: Color {
        switch self {
        case .high: Theme.green
        case .medium: Theme.amber
        case .low: Theme.red
        }
    }

    var label: String { rawValue.capitalized }

    /// How much of the three-step meter it fills.
    var steps: Int {
        switch self {
        case .high: 3
        case .medium: 2
        case .low: 1
        }
    }
}

extension WorkReview.Check.Status {
    var tint: Color {
        switch self {
        case .passed: Theme.green
        case .failed: Theme.red
        case .notRun: Theme.amber
        }
    }

    var symbol: String {
        switch self {
        case .passed: "checkmark"
        case .failed: "xmark"
        case .notRun: "minus"
        }
    }

    var spoken: String {
        switch self {
        case .passed: "passed"
        case .failed: "failed"
        case .notRun: "not run"
        }
    }
}
