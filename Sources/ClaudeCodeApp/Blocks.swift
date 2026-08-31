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
    /// `block` for a gate an agent cannot pass, `proposal` for work product wants to add.
    /// Both are the same thing to this folder — something only the user can settle — and
    /// differ only in who is sent to settle it.
    let kind: String
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

    var waiting: Bool { status != "done" }
    var isProposal: Bool { kind == "proposal" }
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
        return UserBlock(
            id: NotebookEntry.id(for: url),
            url: url,
            slug: slug,
            title: fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? slug,
            status: fields["status"].flatMap { $0.isEmpty ? nil : $0 } ?? "open",
            kind: fields["kind"].flatMap { $0.isEmpty ? nil : $0 } ?? "block",
            session: fields["session"].flatMap(UUID.init(uuidString:)),
            action: fields["action"] ?? "",
            link: link?.scheme?.hasPrefix("http") == true ? link : nil,
            task: fields["task"].flatMap { $0.isEmpty ? nil : $0 },
            resolution: fields["resolution"] ?? "",
            body: NotebookIndex.body(text)
        )
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
