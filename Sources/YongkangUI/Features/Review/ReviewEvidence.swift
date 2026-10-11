import SwiftUI
import YongkangCore

/// What changed, as outcomes someone can see or check rather than files, with the agent's full
/// report one click below for the reviewer who wants its own words.
struct ReviewChanged<Report: View>: View {
    let changed: [String]
    @ViewBuilder let report: () -> Report

    @State private var showing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What changed")
            // One text, so a drag copies as many outcomes as it covers, not one at a time.
            if !changed.isEmpty {
                changed.enumerated().reduce(Text("")) { text, outcome in
                    text + Text(outcome.offset == 0 ? "" : "\n") + Text("•  ").foregroundStyle(Theme.accent)
                        + Text(outcome.element).foregroundStyle(Theme.tx)
                }
                .font(Typography.body).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            Button(showing ? "Hide the agent’s report" : "Read the agent’s full report") { showing.toggle() }
                .buttonStyle(.plain).font(Typography.body).foregroundStyle(Theme.accent)
            if showing { report() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }
}

/// Why the work is safe to take: each check the agent ran, what it proved and what it printed
/// one click away, then what keeps it safe whatever the code does. A check that could not run
/// is listed in amber rather than left out — what nobody checked is what a reviewer reads.
struct ReviewSafety: View {
    let checks: [WorkReview.Check]
    let holds: [String]

    @State private var unfolded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Why it’s safe", trailing: checks.isEmpty ? nil : "open a check for its output")
            if checks.isEmpty {
                Text("The agent ran no checks — nobody but you has checked this.")
                    .font(Typography.body).foregroundStyle(Theme.amber)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                        if index > 0 { Rectangle().fill(Theme.wellLine).frame(height: 1) }
                        checkRow(check, index)
                    }
                }
                .background(Theme.well)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.wellLine, lineWidth: 1))
            }
            if !holds.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Holds by construction").font(Typography.body(.semibold)).foregroundStyle(Theme.tx2)
                    holds.enumerated().reduce(Text("")) { text, held in
                        text + Text(held.offset == 0 ? "" : "\n") + Text("✓  ").foregroundStyle(Theme.green)
                            + Text(held.element).foregroundStyle(Theme.prose)
                    }
                    .font(Typography.body).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    /// The claim and its result are text to select, so only the chevron unfolds the output: a
    /// row that was one button could not have its words copied.
    private func checkRow(_ check: WorkReview.Check, _ index: Int) -> some View {
        let open = unfolded.contains(index)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: check.status.symbol)
                    .font(Typography.caption(.bold)).foregroundStyle(check.status.tint)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(check.status.tint.opacity(0.12)))
                    .accessibilityLabel(check.status.spoken)
                Text(check.claim).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                    .textSelection(.enabled)
                if let result = check.result {
                    Text(result).font(Typography.body)
                        .foregroundStyle(check.status == .passed ? Theme.tx2 : check.status.tint)
                        .lineLimit(open ? nil : 1)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                if check.command != nil {
                    Button {
                        if open { unfolded.remove(index) } else { unfolded.insert(index) }
                    } label: {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(Typography.caption(.semibold)).foregroundStyle(Theme.tx3)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(open ? "Hide the output" : "Show what it ran and printed")
                    .accessibilityLabel(
                        open ? "Hide the output of \(check.claim)" : "Show the output of \(check.claim)")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            if open, let command = check.command {
                Text(command).font(Typography.code).foregroundStyle(Theme.prose)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
                    .padding(.leading, 41).padding(.trailing, 12).padding(.bottom, 10)
            }
        }
    }
}

/// The concerns the agent raised, each saying whether it stands in the way of approving.
struct ReviewConcerns: View {
    let concerns: [WorkReview.Concern]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Concerns it raised")
            ForEach(Array(concerns.enumerated()), id: \.offset) { _, concern in
                let blocks = concern.blocks == true
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(Typography.body).foregroundStyle(blocks ? Theme.red : Theme.amber)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(concern.title).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                                .textSelection(.enabled)
                            NotebookStyle.pill(
                                blocks ? "Settle before approving" : "Doesn’t block this",
                                blocks ? Theme.red : Theme.tx3)
                        }
                        if let detail = concern.detail {
                            Text(detail).font(Typography.body).foregroundStyle(Theme.prose)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }
}

/// What the agent did beyond this repo, and what landing the work unblocks: the inspector's
/// part of a review. An empty `outside` is said out loud, since nothing is the answer wanted.
struct ReviewReach: View {
    let outside: [WorkReview.Outside]
    let next: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Outside the repo")
            if outside.isEmpty {
                Text("Nothing: no network, no downloads, no writes beyond this folder.")
                    .font(Typography.body).foregroundStyle(Theme.tx2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(outside.enumerated()), id: \.offset) { _, call in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    NotebookStyle.pill(call.kind, tint(call.kind))
                    Text(call.what).font(Typography.body).foregroundStyle(Theme.prose)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
        if let next {
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel("Unblocks next")
                Text(next).font(Typography.body).foregroundStyle(Theme.prose).fixedSize(
                    horizontal: false, vertical: true
                )
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 15)
        }
    }

    /// A write anywhere outside the repo is the one a reviewer has to see, so it is the loud one.
    private func tint(_ kind: String) -> Color {
        switch kind {
        case "read": Theme.green
        case "write": Theme.amber
        default: Theme.accent
        }
    }
}
