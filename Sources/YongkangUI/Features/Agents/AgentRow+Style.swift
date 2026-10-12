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
    /// Who it is: the session's own name, "Claude Code 2" or "Product".
    var name: String { session?.title ?? title }

    /// What the sidebar calls it: the task it is on, "Astro project scaffold", the request a
    /// Product is on, "Open source and release" — or a plain shell was given, as its program
    /// titled it — or its own name when it is on neither.
    var label: String { request ?? (task == nil ? name : title) }

    /// The coding agent it runs, "Codex", or its own name for a service runner.
    var agentName: String { session?.agent?.displayName ?? name }

    /// What it is doing, in a word or three: "asks a question", "blocked", "demo ready". Why —
    /// the question, the block — is its `reason`, which the card and the agent page spell out.
    var doing: String {
        switch state {
        case .needsYou:
            // "your turn" rather than "asks a question": with no block it is either a question
            // on its screen or a turn it has finished, and `reason` — which the card and the
            // agent page spell out — is what says which.
            guard let block else { return "your turn" }
            return block.isProposal ? "wants your opinion" : block.isDemo ? "demo ready" : "blocked"
        case .review: return "ready for review"
        // A gate on a working row is one an agent is clearing for you, which is worth its own
        // word: "working" would hide that the task is still held up.
        case .working:
            if block != nil { return "setting up" }
            if session?.isTerminal == true { return "terminal" }
            return session?.agent == nil ? "running" : "working"
        }
    }

    /// The other project it is talking to, while it has nothing to ask you: then that is its line.
    var talkingTo: Peer? { state == .working ? peer : nil }

    /// What it is doing, then the coding agent doing it: "working · Codex". A session on no task
    /// is already named after itself, so it says only the first. One talking to another project
    /// says which instead: "waiting on notebook-sync". One named after its request says who it
    /// is first: "Product · your turn", "yongkang · terminal".
    var line: String {
        let line =
            talkingTo.map { "\($0.verb) \($0.project)" } ?? (task == nil ? doing : "\(doing) · \(agentName)")
        return request == nil ? line : "\(name) · \(line)"
    }

    /// What it is doing, as a request's card says it: who it is waiting on, rather than that
    /// it is working, while the answer is what it is waiting for.
    var requestDoing: String {
        if state == .working, case .waitingOn(let project)? = peer { return "waiting on \(project)" }
        return doing
    }

    /// A task's line: what is happening on it, then who is on it: "working · Codex".
    var byLine: String { session.map { "\(doing) · \($0.title)" } ?? doing }
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
