import Foundation

/// One thing an agent cannot do for itself — a credential, a consent screen, an approval
/// — written to `.notebook/blocks/<slug>.md` by whoever hit the gate and read back here.
///
/// A file rather than a message: the agents already write Markdown, the app already polls
/// this folder, and the answer travels the same way back — the session that clears the
/// block sets `status: done` in the file, and the app types the news into whichever
/// session was waiting. Nothing here holds a secret; only what is now configured.
struct UserBlock: Identifiable, Equatable {
    /// The file path, so selection survives the reload — same rule as `NotebookEntry`.
    let id: String
    let url: URL
    let slug: String
    let title: String
    let status: String
    /// `block` for a gate an agent cannot pass, `proposal` for work product wants to add,
    /// `demo` for a design a task cannot be built without your approval of. All three are
    /// the same thing to this folder — something only the user can settle — and differ
    /// only in who is sent to settle it.
    let kind: String
    /// Product proposals are discussed in their transcript before they are ready to
    /// create. Old proposal files predate this field and are already approval-ready.
    let stage: String
    /// The session waiting on this, when it named itself. Nil routes to the newest lead.
    let session: UUID?
    /// What the session started by the button is told to get done.
    let action: String
    /// The provider page the user has to be on. Opened alongside that session.
    let link: URL?
    /// The task this holds up, shown so the sidebar row says what it is costing.
    let task: String?
    /// One line about what is now configured, written by whoever cleared it.
    let resolution: String
    let body: String
    /// Demos only: the page as it stands, so the two can be shown side by side. Nil when
    /// the task adds a surface that does not exist yet — there is honestly no before.
    let before: URL?
    /// Demos only: the throwaway branch the demo runs on, named so it is obvious nothing
    /// has landed. Approving turns it into the build; rejecting throws it away.
    let branch: String
    /// Demos only: every pass the designer made, oldest first, so the change can be
    /// followed rather than arriving as one finished thing.
    let revisions: [DemoRevision]

    var waiting: Bool { status != "done" }
    var isProposal: Bool { kind == "proposal" }
    var proposalReady: Bool { isProposal && stage == "ready" }
    /// A design waiting on the user before any engineer starts on its task.
    var isDemo: Bool { kind == "demo" }
}

/// One pass of a demo. `url` is whatever the designer left running or published for that
/// pass; without one the revision is still listed — the note is the record — but only the
/// passes that kept a URL can be opened again.
struct DemoRevision: Identifiable, Equatable {
    let id: Int
    let label: String
    let note: String
    let url: URL?
}

enum Blocks {
    static let folderName = "blocks"

    static func root(in notebookRoot: URL) -> URL { notebookRoot.appendingPathComponent(folderName) }

    /// Empty until something is actually blocked — the folder is not scaffolded.
    static func load(root: URL) -> [UserBlock] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Blocks.root(in: root),
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(block(at:))
    }

    /// Anything in `blocks/` counts, whatever its frontmatter says. A block written a
    /// little wrong still has to reach the user — a block that silently fails to show up
    /// is the one failure this folder exists to prevent.
    static func block(at url: URL) -> UserBlock? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
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
    static func revisions(_ body: String) -> [DemoRevision] {
        let lines = body.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## revisions")
        }) else { return [] }

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
    static func resolve(_ block: UserBlock) {
        guard let text = try? String(contentsOf: block.url, encoding: .utf8),
              let line = text.range(of: "\nstatus: \(block.status)") else { return }
        let updated = text.replacingCharacters(in: line, with: "\nstatus: done")
        try? updated.write(to: block.url, atomically: true, encoding: .utf8)
    }
}
