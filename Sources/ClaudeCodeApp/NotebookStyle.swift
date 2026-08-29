import SwiftUI

/// Status color and glyphs shared by every place a notebook entry's status shows up —
/// the board's cards and a project's own detail page draw the same language.
enum NotebookStyle {
    static func color(of status: String) -> Color {
        switch status {
        case "done": return .green
        case "active": return .blue
        case "blocked": return .orange
        case "wip": return .purple
        default: return .gray
        }
    }

    static func pill(_ status: String) -> some View {
        Text(status)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color(of: status))
            .background(Capsule().fill(color(of: status).opacity(0.15)))
    }

    /// Linear's issue-status glyph: an outline in the status color, filled in as tasks
    /// complete, swapped for a solid check once the project itself is done.
    static func statusRing(_ status: String, progress: Double, size: CGFloat = 13) -> some View {
        ZStack {
            Circle().stroke(color(of: status).opacity(0.3), lineWidth: 2)
            if status == "done" {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size))
                    .foregroundStyle(.green)
            } else if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color(of: status), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }

    /// The other end of a `depends_on` edge: what is held up by this card.
    /// `depends_on` only points one way, so without this a card cannot say what is
    /// waiting on it.
    static func dependents(of card: NotebookCard, in cards: [NotebookCard]) -> [String] {
        cards.filter { $0.dependsOn.contains(card.id) }.map(\.id)
    }

    /// Unknown ids show in orange — a typo in `depends_on` is otherwise invisible.
    static func edge(_ label: String, _ ids: [String], in cards: [NotebookCard]) -> Text? {
        guard !ids.isEmpty else { return nil }
        return ids.reduce(Text(label).foregroundColor(.secondary)) { text, id in
            let known = cards.contains { $0.id == id }
            let separator = id == ids.first ? "" : ", "
            return text + Text(separator).foregroundColor(.secondary)
                + Text(known ? id : "\(id)?").foregroundColor(known ? .secondary : .orange)
        }
    }
}
