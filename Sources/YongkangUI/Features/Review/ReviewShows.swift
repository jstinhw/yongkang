import SwiftUI
import YongkangCore

/// The change itself, its before beside its after: what a reviewer looks at before any code. A
/// screen is the app running as it was and as it is, an error case what it did then and does
/// now, and a schema or an API its old and new text with the lines that differ lit.
struct ReviewShows: View {
    let shows: [WorkReview.Show]
    /// The task, which names the terminal a screen's side is served in.
    let task: String
    let serve: (_ url: URL, _ command: String, _ title: String) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("See the change", trailing: shows.count == 1 ? nil : "\(shows.count) views")
            ForEach(Array(shows.enumerated()), id: \.offset) { index, show in
                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                showRow(show)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private func showRow(_ show: WorkReview.Show) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NotebookStyle.pill(label(show.kind), tint(show.kind))
                Text(show.title).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                    .textSelection(.enabled)
                if let test = show.test {
                    Text(test).font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if show.kind == "ui" {
                ReviewLive(show: show, task: task, serve: serve)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    side(show, before: true)
                    side(show, before: false)
                }
            }
            if let note = show.note {
                Text(note).font(Typography.body).foregroundStyle(Theme.prose)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(radius: 10, padding: 10, border: Theme.wellLine, fill: Theme.well)
            }
        }
    }

    private func side(_ show: WorkReview.Show, before: Bool) -> some View {
        let text = before ? show.before : show.after
        let color = before ? Theme.problem : Theme.insertion
        let error = show.kind == "error"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if error {
                    Image(systemName: before ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(before ? Theme.red : Theme.green)
                }
                Text(before ? "BEFORE" : "AFTER").font(Typography.section).tracking(1.2).foregroundStyle(color)
            }
            if text == nil {
                Text(before ? "Nothing: it is new" : "Gone").font(Typography.body).foregroundStyle(Theme.tx3)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .cardSurface(radius: 8, padding: 8, border: Theme.wellLine, fill: Theme.well)
            } else {
                lines(show, before: before)
                    .cardSurface(
                        radius: 8, padding: 0, border: error ? color.opacity(0.3) : Theme.wellLine,
                        fill: error ? color.opacity(0.06) : Theme.panel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One side's text, each line its own row so the ones the other side lacks can be lit. An
    /// error case is all one colour: both sides are the whole of what happened.
    private func lines(_ show: WorkReview.Show, before: Bool) -> some View {
        let old = (show.before ?? "").components(separatedBy: "\n")
        let new = (show.after ?? "").components(separatedBy: "\n")
        var lit: Set<Int> = []
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): if before { lit.insert(offset) }
            case .insert(let offset, _, _): if !before { lit.insert(offset) }
            }
        }
        let error = show.kind == "error"
        let color = before ? Theme.problem : Theme.insertion
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((before ? old : new).enumerated()), id: \.offset) { index, line in
                let on = error || lit.contains(index)
                Text(line.isEmpty ? " " : line).font(Typography.code).foregroundStyle(on ? color : Theme.unchanged)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 1)
                    .background(on && !error ? color.opacity(0.08) : .clear)
            }
        }
        .padding(.vertical, 8)
        .textSelection(.enabled)
    }

    private func label(_ kind: String) -> String {
        switch kind {
        case "ui": return "UI"
        case "error": return "Error case"
        default: return kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }

    private func tint(_ kind: String) -> Color {
        switch kind {
        case "ui": return Theme.accent
        case "error": return Theme.red
        case "schema": return Theme.violet
        case "api": return Theme.amber
        default: return Theme.tx2
        }
    }
}
