import SwiftUI
import YongkangCore

/// The few places the agent says are worth reading because no check or show covers them, each
/// unfolding its own lines of the diff, where a line can be commented on. Optional reading, so
/// it sits under the evidence and never counts as something the work waits on.
struct ReviewSpots: View {
    let spots: [WorkReview.Spot]
    /// The diffs of the task's files, read when the page opened; empty until then.
    let diffs: [String: [DiffLine]]
    let loading: Bool
    @Binding var draft: ReviewDraft
    let openFile: (String) -> Void

    /// The spot unfolded, none to begin with: the page opens on why to look, and the code is
    /// one click away.
    @State private var open: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Worth a read", trailing: "optional")
            ForEach(Array(spots.enumerated()), id: \.offset) { index, spot in spotRow(spot, index) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    /// The path and the reason are text to select, so only the chevron unfolds the excerpt.
    private func spotRow(_ spot: WorkReview.Spot, _ index: Int) -> some View {
        let unfolded = open == index
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                Text("\(index + 1)").font(Typography.caption(.bold)).foregroundStyle(Theme.tx2)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.raised))
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
