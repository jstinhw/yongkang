import SwiftUI
import YongkangCore

extension AgentRow.State {
    /// The notebook's own status colours: amber is waiting on you, green is waiting for your
    /// review, blue is at work.
    var color: Color {
        switch self {
        case .needsYou: return Theme.amber
        case .review: return Theme.green
        case .working: return Theme.accent
        }
    }

    /// What a column of these is called, on the project's Agents page.
    var title: String {
        switch self {
        case .needsYou: return "Needs you"
        case .review: return "Ready for review"
        case .working: return "Working"
        }
    }
}

extension AgentRow {
    /// Who it is — the session's own name, "Claude Code 2" or "Product" — then why it is where it
    /// is: "Codex · asks before running swift test".
    var line: String {
        guard let session else { return reason ?? state.title.lowercased() }
        let who = session.title
        switch state {
        case .needsYou: return "\(who) · \(reason ?? "needs you")"
        case .review: return "\(who) · ready for review"
        case .working: return "\(who) · \(session.agent == nil ? "running" : "working")"
        }
    }
}

/// The mark beside an agent's name: a lit dot for waiting on you, a tick for waiting for your
/// review, a quarter ring for working — the same three the board's cards use.
struct AgentStateGlyph: View {
    let state: AgentRow.State
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch state {
            case .needsYou:
                StateDot(color: Theme.amber, live: true)
            case .review:
                Image(systemName: "checkmark.circle")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(Theme.green)
            case .working:
                ZStack {
                    Circle().stroke(Theme.hairline, lineWidth: 1.6)
                    Circle().trim(from: 0, to: 0.25)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
