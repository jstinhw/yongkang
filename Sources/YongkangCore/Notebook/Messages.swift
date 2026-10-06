import Foundation

/// What an agent here has to say to another open project — written to
/// `.notebook/messages/<slug>.md` in its own notebook, never the receiver's, and read back here
/// so the app can type it into a session there.
///
/// Like `blocks/` it is a channel to the app rather than notebook content, so
/// `NotebookFormat.specText` does not list it. The app never writes these files: what it has
/// delivered it remembers itself.
package struct ProjectMessage: Identifiable, Equatable, Sendable {
    /// The file path, so what was delivered can be remembered across reads — same rule as
    /// `NotebookEntry`.
    package let id: String
    package let url: URL
    /// The receiving project's folder, relative to the sender's, as the tag reached the agent.
    /// Matched against the open projects by whoever delivers it.
    package let to: String
    /// The session that wrote it, which the answer comes back to.
    package let session: UUID
    /// The session there this answers. Nil for a first message, which goes to that project's
    /// Product.
    package let replyTo: UUID?
    package let title: String
    package let body: String

    package init(id: String, url: URL, to: String, session: UUID, replyTo: UUID?, title: String, body: String) {
        self.id = id
        self.url = url
        self.to = to
        self.session = session
        self.replyTo = replyTo
        self.title = title
        self.body = body
    }
}

package enum Messages {
    static let folderName = "messages"

    static func root(in notebookRoot: URL) -> URL { notebookRoot.appendingPathComponent(folderName) }

    /// Empty until an agent writes to another project — the folder is not scaffolded.
    package static func load(root: URL) -> [ProjectMessage] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: Messages.root(in: root),
                includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(message(at:))
    }

    /// Unlike a block, a message written wrong is dropped rather than shown: one with nowhere
    /// to go or nobody to answer cannot be delivered, and a `reply_to` that is not a session id
    /// would otherwise fall through to a fresh Product as if it were a first message.
    static func message(at url: URL) -> ProjectMessage? {
        guard let text = Log.contents(of: url) else { return nil }
        let fields = NotebookIndex.frontmatter(text)
        guard let to = fields["to"], !to.isEmpty,
            let session = fields["session"].flatMap(UUID.init(uuidString:))
        else { return nil }
        let reply = fields["reply_to"] ?? ""
        let replyTo = UUID(uuidString: reply)
        guard reply.isEmpty || replyTo != nil else { return nil }
        let slug = url.deletingPathExtension().lastPathComponent
        return ProjectMessage(
            id: NotebookEntry.id(for: url),
            url: url,
            to: to,
            session: session,
            replyTo: replyTo,
            title: fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? slug,
            body: NotebookIndex.body(text))
    }
}
