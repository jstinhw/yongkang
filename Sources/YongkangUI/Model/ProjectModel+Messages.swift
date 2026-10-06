import CryptoKit
import Foundation
import YongkangCore

/// One message, routed: the session it goes to and what to type there. `text` is nil when the
/// session was started on it as its prompt, which leaves nothing to type.
struct Delivery: Equatable {
    /// What `AppModel.deliveredMessages` remembers it by. See `ProjectMessage.deliveryKey`.
    let key: String
    let session: UUID
    let text: String?
}

extension ProjectModel {
    /// What this project's agents wrote to other projects and nobody has been told yet, each
    /// routed among the open `projects`:
    ///
    /// - a `reply_to` naming a running session there is typed into that session, as it is;
    /// - anything else goes to that project's Product, started if none is running, and its
    ///   board treats it as a request this project asked;
    /// - a `to` naming no open project is answered in the sender's session, in one line.
    ///
    /// Sessions are all it touches, never the window: the caller types what this returns and
    /// goes nowhere. A message nobody can be told about — its project not open, its sender
    /// gone — is left for a later read, which may find that project open.
    func deliveries(among projects: [ProjectModel], skipping delivered: Set<String>, agent: AgentKind) -> [Delivery] {
        var routed: [Delivery] = []
        // As a folder: resolved against a base with no trailing slash, `../sync` would go one up too far.
        let here = URL(fileURLWithPath: directory.path, isDirectory: true)
        for message in snapshot.messages where !delivered.contains(message.deliveryKey) {
            let folder = URL(fileURLWithPath: message.to, relativeTo: here).standardizedFileURL.path
            guard
                let receiver = projects.first(where: { !$0.missing && $0.directory.standardizedFileURL.path == folder })
            else {
                guard isRunning(message.session) else { continue }
                let file = NotebookFormat.relativePath(message.url)
                routed.append(
                    Delivery(
                        key: message.deliveryKey, session: message.session,
                        text: NotebookFormat.undeliveredMessage(to: message.to, file: file)))
                continue
            }
            guard let (session, text) = receiver.receive(message, from: directory, agent: agent) else { continue }
            waitingOn[message.session] = receiver.directory
            if let asking = request, asking.session == message.session, asking.from == nil {
                request?.asked = BoardRequest.Ask(project: receiver.directory, title: message.title)
            }
            routed.append(Delivery(key: message.deliveryKey, session: session, text: text))
        }
        return routed
    }

    /// A message from the project in `sender`: into the session its `reply_to` names while that
    /// runs here, or else to Product as `asked`, which files its part on this board. The board
    /// then shows it as a request, unless Product is already on one — what it filed for that is
    /// still new. Returns the session it went to and what is left to type into it.
    func receive(_ message: ProjectMessage, from sender: URL, agent: AgentKind) -> (UUID, String?)? {
        let text = NotebookFormat.incomingMessage(
            from: Mention.relative(sender, from: directory), session: message.session.uuidString.lowercased(),
            title: message.title, body: message.body)
        if let reply = message.replyTo, isRunning(reply) {
            waitingOn[reply] = nil
            return (reply, text)
        }
        let sent = startProduct("asked\n" + text, agent: agent, reading: [sender])
        guard case .session(let product, _)? = sent.route else { return nil }
        if request?.session != product {
            request = BoardRequest(session: product, before: Set(cards.map(\.id)), from: sender)
        }
        return (product, sent.input)
    }

    private func isRunning(_ id: UUID) -> Bool { sessions.contains { $0.id == id && !$0.exited } }
}

extension ProjectMessage {
    /// Its file and what is in it, so a slug an agent writes again with a new message is a new
    /// delivery, while the same message read again is not. Hashed, because the keys are kept in
    /// defaults, which is no place for what agents say to each other.
    var deliveryKey: String {
        let content = [to, session.uuidString, replyTo?.uuidString ?? "", title, body].joined(separator: "\n")
        return id + "#" + SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
