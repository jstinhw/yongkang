import SwiftUI
import YongkangCore

/// Status colour and glyphs shared by every place a notebook entry's status shows up —
/// the board's cards, a project's page, an agent's row. The words are the notebook's own
/// `status:` values; the colours come from `Theme`, so there is one palette, not two.
package enum NotebookStyle {
    static func color(of status: String) -> Color {
        switch status {
        case "done", "succeeded", "passed": return Theme.green
        case "active", "running": return Theme.accent
        case "blocked", "partial", "waiting": return Theme.amber
        case "failed": return Theme.red
        // Design and QA share violet the way SRE and FDE share amber: both are somebody
        // holding the work who is not building it.
        case "wip", "assigned", "designing": return Theme.violet
        default: return Theme.tx2
        }
    }

    static func pill(_ status: String) -> some View {
        pill(status, color(of: status))
    }

    /// The one badge shape in the app: 20pt tall, the signal colour on a wash of itself.
    package static func pill(_ text: String, _ color: Color, live: Bool = false) -> some View {
        HStack(spacing: 5) {
            if live { StateDot(color: color, live: true) }
            Text(text).font(Typo.text(11, .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, live ? 9 : 8)
        .frame(height: 20)
        .background(Capsule().fill(color.opacity(0.13)))
    }

    /// A chip for a fact rather than a state: an id, a role, a count.
    static func chip(_ text: String, mono: Bool = false) -> some View {
        Text(text)
            .font(mono ? Typo.mono(10) : Typo.text(11))
            .foregroundStyle(Theme.tx2)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.chipLine, lineWidth: 1))
    }

    /// Linear's issue-status glyph: an outline in the status colour, filled in as tasks
    /// complete, swapped for a solid check once the work itself is done.
    static func statusRing(_ status: String, progress: Double, size: CGFloat = 13) -> some View {
        let tint = color(of: status)
        return ZStack {
            Circle().stroke(tint.opacity(0.28), lineWidth: 2)
            if status == "done" {
                Circle().fill(Theme.green.opacity(0.14))
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Theme.green)
            } else if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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

    /// Unknown ids show in amber — a typo in `depends_on` is otherwise invisible.
    static func edge(_ label: String, _ ids: [String], in cards: [NotebookCard]) -> Text? {
        guard !ids.isEmpty else { return nil }
        return ids.reduce(Text(label).foregroundColor(Theme.tx3)) { text, id in
            let known = cards.contains { $0.id == id }
            let separator = id == ids.first ? "" : ", "
            return text + Text(separator).foregroundColor(Theme.tx3)
                + Text(known ? id : "\(id)?").foregroundColor(known ? Theme.tx2 : Theme.amber)
        }
    }
}
