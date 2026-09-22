import Foundation
import YongkangCore

/// Every CLI asks, before anything else, whether it may work in a folder it has no answer for,
/// and asks it again in each session. So the answer is got once, before any work is handed
/// over: the work's own sessions then start already allowed, and none of them asks.
extension ProjectModel {
    /// Whether the records may be read again: at most every 30 s, because Grok's is a process.
    /// An answer given in a session is read straight away instead (`trustGranted`).
    func trustReadIsDue(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastTrustRead) >= 30
    }

    /// Asks each of `agents`' own records again whether it may work here. One that can't be
    /// read right now leaves its agent as it was.
    func readTrust(_ agents: Set<AgentKind>) async {
        lastTrustRead = Date()
        var untrusted = self.untrusted
        for agent in agents {
            guard let trusted = await trustRecord(agent, directory) else { continue }
            if trusted || allowedThisRun.contains(agent) { untrusted.remove(agent) } else { untrusted.insert(agent) }
        }
        if untrusted != self.untrusted { self.untrusted = untrusted }
    }

    /// A session of `agent` opened for that one question. Nil while its record allows it, and
    /// while a session of it runs here already: that one is asking, or was answered.
    func askToTrust(_ agent: AgentKind) -> Destination? {
        guard untrusted.contains(agent), !sessions.contains(where: { $0.agent == agent && !$0.exited })
        else { return nil }
        let id = UUID()
        trustSession = id
        return Destination(section: .agents, route: addSession(agent, id: id))
    }

    /// Reads the record of the CLI whose question just cleared in `session`. True when that was
    /// the session `askToTrust` opened and the record now allows it: it was answered yes, and
    /// the session has nothing left to do.
    func trustGranted(by session: UUID) async -> Bool {
        guard let agent = sessions.first(where: { $0.id == session })?.agent else { return false }
        await readTrust([agent])
        guard session == trustSession, !untrusted.contains(agent) else { return false }
        trustSession = nil
        return true
    }

    /// True when the session `askToTrust` opened is still running and asking nothing, a while
    /// after it started or after an answer its record didn't show. Its CLI asks nothing more,
    /// so the record was misread, or lost (Claude Code has lost its own before), and the agent
    /// is let in for the rest of this run rather than leaving the work unable to start.
    func trustSettled(by session: UUID, asking: Bool) -> Bool {
        guard session == trustSession, !asking,
            let agent = sessions.first(where: { $0.id == session && !$0.exited })?.agent
        else { return false }
        trustSession = nil
        allowedThisRun.insert(agent)
        untrusted.remove(agent)
        return true
    }
}
