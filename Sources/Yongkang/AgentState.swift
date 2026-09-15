import Foundation

/// What an agent is doing right now. A subagent's own file answers this exactly — it was
/// spawned to finish one thing and then stops. A session never stops: it works, then sits
/// at its prompt with the answer on screen, which is a different thing from being done and
/// the one the reader has to be told about, because it is their turn.
package enum AgentState {
    case starting, working, waiting, done, exited

    package var label: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .waiting: return "Waiting for you"
        case .done: return "Done"
        case .exited: return "Exited"
        }
    }

    package var live: Bool { self == .starting || self == .working }

    /// A session's state, off the transcript it is already showing: the last thing written
    /// was the agent talking to the user, so it has nothing in flight and is waiting to be
    /// answered. Anything else — a tool call, a result, the brief — is work in progress.
    package static func of(lines: [TranscriptLine], exited: Bool) -> AgentState {
        guard !exited else { return .exited }
        guard let last = lines.last else { return .starting }
        return last.label == "Reply" ? .waiting : .working
    }
}
