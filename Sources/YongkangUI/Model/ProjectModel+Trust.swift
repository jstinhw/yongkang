import Foundation
import YongkangCore

extension ProjectModel {
    /// A session of `agent` opened for the one thing its CLI asks first in a folder its record
    /// doesn't allow it in: whether it may work here. Asked before any work is handed over, so
    /// the work's own sessions start already allowed, and none of them asks.
    ///
    /// Nil while the record allows it, and while a session of it runs here already: that one
    /// is asking, or was answered.
    func askToTrust(_ agent: AgentKind) -> Destination? {
        guard untrusted.contains(agent), !sessions.contains(where: { $0.agent == agent && !$0.exited })
        else { return nil }
        let id = UUID()
        trustSession = id
        return Destination(section: .agents, route: addSession(agent, id: id))
    }

    /// Whether `session` is the one `askToTrust` opened and its CLI's record now allows it here:
    /// the question was answered yes, and the session has nothing left to do.
    func trustGranted(by session: UUID) async -> Bool {
        await readTrust()
        guard session == trustSession, let agent = sessions.first(where: { $0.id == session })?.agent,
            !untrusted.contains(agent)
        else { return false }
        trustSession = nil
        return true
    }
}
