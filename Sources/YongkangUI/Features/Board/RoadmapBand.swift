import SwiftUI
import YongkangCore

/// A roadmap across the top of the board: what the goal is and how far its milestones have got.
/// A roadmap no milestone names is the project's only one, and gets them all.
struct RoadmapBand: View {
    let roadmap: NotebookCard
    let cards: [NotebookCard]
    let open: () -> Void

    var body: some View {
        let named = cards.filter { $0.kind == .project && $0.roadmap == roadmap.id }
        let milestones = named.isEmpty ? cards.filter { $0.kind == .project } : named
        let ids = Set(milestones.map(\.id))
        let work = cards.filter { $0.kind == .task && ids.contains($0.project ?? "") }
        let done = work.filter { $0.status == "done" }.count
        let finished = milestones.filter { NotebookIndex.isFinished($0, in: cards) }.count
        return Button(action: open) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Roadmap")
                    Text(roadmap.title).font(Typography.headline).foregroundStyle(Theme.tx)
                    if let brief = NotebookIndex.brief(of: roadmap.body) {
                        Text(brief).font(Typography.body).foregroundStyle(Theme.prose).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(done) of \(work.count) tasks done").font(Typography.caption).foregroundStyle(
                            Theme.prose)
                        Spacer(minLength: 4)
                        Text(work.isEmpty ? "–" : "\(done * 100 / work.count)%").font(Typography.mono)
                            .foregroundStyle(Theme.tx3)
                    }
                    MeterBar(value: work.isEmpty ? 0 : Double(done) / Double(work.count))
                    Text("\(milestones.count) milestone\(milestones.count == 1 ? "" : "s") · \(finished) done")
                        .font(Typography.caption).foregroundStyle(Theme.tx3)
                }
                .frame(width: 240)
            }
            .cardSurface(radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
