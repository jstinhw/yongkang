import Foundation

/// One thing an agent cannot do for itself — a credential, a consent screen, an approval
/// — written to `.notebook/blocks/<slug>.md` by whoever hit the gate and read back here.
///
/// A file rather than a message: the agents already write Markdown, the app already polls
/// this folder, and the answer travels the same way back — the session that clears the
/// block sets `status: done` in the file, and the app types the news into whichever
/// session was waiting. Nothing here holds a secret; only what is now configured.
package struct UserBlock: Identifiable, Equatable, Sendable {
    /// The file path, so selection survives the reload — same rule as `NotebookEntry`.
    package let id: String
    package let url: URL
    package let slug: String
    package let title: String
    let status: String
    /// `block` for a gate an agent cannot pass, `proposal` for work product wants to add,
    /// `demo` for a design a task cannot be built without your approval of. All three are
    /// the same thing to this folder — something only the user can settle — and differ
    /// only in who is sent to settle it.
    let kind: String
    /// Product proposals are discussed in their transcript before they are ready to
    /// create. Old proposal files predate this field and are already approval-ready.
    let stage: String
    /// The session waiting on this, when it named itself. Nil routes to the newest assigned session.
    package let session: UUID?
    /// What the session started by the button is told to get done.
    package let action: String
    /// The provider page the user has to be on. Opened alongside that session.
    package let link: URL?
    /// The task this holds up, shown so the sidebar row says what it is costing.
    package let task: String?
    /// One line about what is now configured, written by whoever cleared it.
    package let resolution: String
    package let body: String
    /// Demos only: the page as it stands, so the two can be shown side by side. Nil when
    /// the task adds a surface that does not exist yet — there is honestly no before.
    package let before: URL?
    /// Demos only: the throwaway branch the demo runs on, named so it is obvious nothing
    /// has landed. Approving turns it into the build; rejecting throws it away.
    package let branch: String
    /// Demos only: every pass the designer made, oldest first, so the change can be
    /// followed rather than arriving as one finished thing.
    package let revisions: [DemoRevision]

    package init(
        id: String,
        url: URL,
        slug: String,
        title: String,
        status: String,
        kind: String,
        stage: String,
        session: UUID?,
        action: String,
        link: URL?,
        task: String?,
        resolution: String,
        body: String,
        before: URL?,
        branch: String,
        revisions: [DemoRevision]
    ) {
        self.id = id
        self.url = url
        self.slug = slug
        self.title = title
        self.status = status
        self.kind = kind
        self.stage = stage
        self.session = session
        self.action = action
        self.link = link
        self.task = task
        self.resolution = resolution
        self.body = body
        self.before = before
        self.branch = branch
        self.revisions = revisions
    }

    package var waiting: Bool { status != "done" }
    package var isProposal: Bool { kind == "proposal" }
    package var proposalReady: Bool { isProposal && stage == "ready" }
    /// A design waiting on the user before any engineer starts on what it blocks.
    package var isDemo: Bool { kind == "demo" }
    /// A gate an agent hit — a credential, a consent screen, an account. Unlike a demo or a
    /// proposal, which are the user's own to settle, it is something an engineer can be sent
    /// to work through with them, so it is the only kind the app opens a session for.
    package var isGate: Bool { !isProposal && !isDemo }

    /// The title for a session opened only to clear this gate — the fallback, when the agent
    /// that filed it is gone and there is nobody left to hand it back to.
    package var guideTitle: String { "Unblock \(title)" }

    /// The half of the body addressed to the user: the brief, and what is needed from them.
    ///
    /// `## Steps` and everything after it is the procedure — exact pages, exact scopes, exact
    /// commands — written for the engineer who sits with the user, not for the user. Drawing
    /// it was the whole of "the guidance is too lengthy": ten steps, most of them the agent's
    /// own, on a screen opened to find out what was wanted. Every screen that shows a block
    /// shows this, so the answer cannot be right on one and wrong on the next.
    ///
    /// A proposal has no such half and keeps its whole body.
    package var brief: String {
        guard !isProposal else { return body }
        let lines = body.components(separatedBy: "\n")
        guard
            let steps = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## steps")
            })
        else { return body }
        return lines[..<steps].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Collection<UserBlock> {
    /// The one definition of "waiting on you", so two screens cannot count the same folder
    /// differently — which they did: the board listed demos and the sidebar listed everything,
    /// so a gate waiting on a go-ahead was a number in one place and nowhere in the other.
    package var waitingOnUser: [UserBlock] { filter(\.waiting) }

    /// What is waiting on the user on one task. A proposal is never one: it holds up the
    /// notebook rather than a task, and belongs to its Product conversation.
    package func waiting(on task: String) -> UserBlock? {
        waitingOnUser.first { !$0.isProposal && $0.task == task }
    }
}

/// One pass of a demo. `url` is whatever the designer left running or published for that
/// pass; without one the revision is still listed — the note is the record — but only the
/// passes that kept a URL can be opened again.
package struct DemoRevision: Identifiable, Equatable, Sendable {
    package let id: Int
    package let label: String
    package let note: String
    package let url: URL?
}

package enum Blocks {
    static let folderName = "blocks"

    static func root(in notebookRoot: URL) -> URL { notebookRoot.appendingPathComponent(folderName) }

    /// Empty until something is actually blocked — the folder is not scaffolded.
    package static func load(root: URL) -> [UserBlock] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: Blocks.root(in: root),
                includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(block(at:))
    }

    /// Anything in `blocks/` counts, whatever its frontmatter says. A block written a
    /// little wrong still has to reach the user — a block that silently fails to show up
    /// is the one failure this folder exists to prevent.
    static func block(at url: URL) -> UserBlock? {
        guard let text = Log.contents(of: url) else { return nil }
        let fields = NotebookIndex.frontmatter(text)
        let slug = url.deletingPathExtension().lastPathComponent
        let link = fields["url"].flatMap(URL.init(string:))
        let body = NotebookIndex.body(text)
        return UserBlock(
            id: NotebookEntry.id(for: url),
            url: url,
            slug: slug,
            title: fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? slug,
            status: fields["status"].flatMap { $0.isEmpty ? nil : $0 } ?? "open",
            kind: fields["kind"].flatMap { $0.isEmpty ? nil : $0 } ?? "block",
            stage: fields["stage"].flatMap { $0.isEmpty ? nil : $0 } ?? "ready",
            session: fields["session"].flatMap(UUID.init(uuidString:)),
            action: fields["action"] ?? "",
            link: link?.scheme?.hasPrefix("http") == true ? link : nil,
            task: fields["task"].flatMap { $0.isEmpty ? nil : $0 },
            resolution: fields["resolution"] ?? "",
            body: body,
            before: web(fields["before"]),
            branch: fields["branch"] ?? "",
            revisions: revisions(body)
        )
    }

    /// Only an http(s) address is worth handing a web view; anything else in the field is
    /// dropped rather than opened.
    private static func web(_ value: String?) -> URL? {
        guard let url = value.flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return url
    }

    /// The `## Revisions` list out of a demo's body: one `- ` line per pass, oldest first,
    /// its parts separated by `·`. A line the designer wrote a little differently still
    /// lists — the label is whatever came first and the rest is the note.
    package static func revisions(_ body: String) -> [DemoRevision] {
        let lines = body.components(separatedBy: "\n")
        guard
            let start = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## revisions")
            })
        else { return [] }

        var found: [DemoRevision] = []
        for line in lines[(start + 1)...] {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("#") { break }
            guard text.hasPrefix("- ") else { continue }
            let parts = text.dropFirst(2).components(separatedBy: "·")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let label = parts.first else { continue }
            let link = parts.dropFirst().compactMap { web($0) }.last
            let note = parts.dropFirst()
                .filter { web($0) == nil }
                .joined(separator: " · ")
            found.append(DemoRevision(id: found.count, label: label, note: note, url: link))
        }
        return found
    }

    /// Marking a block resolved by hand is the same edit the guiding session makes: the
    /// status line in the frontmatter, and nothing else in the file.
    package static func resolve(_ block: UserBlock) {
        guard let text = try? String(contentsOf: block.url, encoding: .utf8),
            let line = text.range(of: "\nstatus: \(block.status)")
        else { return }
        let updated = text.replacingCharacters(in: line, with: "\nstatus: done")
        try? updated.write(to: block.url, atomically: true, encoding: .utf8)
    }
}
