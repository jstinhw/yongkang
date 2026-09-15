import Foundation

/// What git said about a project's working tree at the last read: the changes under review
/// and the commit and branch they sit on. Replaced whole, like `NotebookSnapshot`.
package struct RepoStatus: Equatable {
    package let changes: [FileChange]
    package let head: String?
    package let branch: String?
    /// The full id of the commit `head` names, so the next read can tell whether `head` still
    /// stands without asking git for it.
    let oid: String?

    package init(changes: [FileChange] = [], head: String? = nil, branch: String? = nil, oid: String? = nil) {
        self.changes = changes
        self.head = head
        self.branch = branch
        self.oid = oid
    }

    /// Two git calls, `status` and `numstat`, plus `log` when the commit has moved since
    /// `previous`. Nil when `directory` is not in a repository.
    package static func read(in directory: URL, after previous: RepoStatus = RepoStatus()) async -> RepoStatus? {
        guard let status = await GitClient.status(in: directory) else { return nil }
        // Before the first commit there is no HEAD to diff against: every file is untracked,
        // and a file already staged is listed nowhere until something is committed.
        let tracked = await status.oid == nil ? [] : GitClient.numstat(in: directory)
        let head = await status.oid == previous.oid ? previous.head : GitClient.head(in: directory)
        let untracked = status.untracked.map {
            FileChange(path: $0, added: lineCount($0, in: directory), removed: 0, untracked: true)
        }
        return RepoStatus(
            changes: (tracked + untracked).sorted { $0.path < $1.path }, head: head, branch: status.branch,
            oid: status.oid)
    }

    private static func lineCount(_ path: String, in directory: URL) -> Int {
        let url = directory.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }
}
