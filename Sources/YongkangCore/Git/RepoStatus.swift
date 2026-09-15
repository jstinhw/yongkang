import Foundation

/// What git said about a project's working tree at the last read: the changes under review
/// and the commit and branch they sit on. Replaced whole, like `NotebookSnapshot`.
package struct RepoStatus: Equatable, Sendable {
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
    ///
    /// Untracked files keep the line counts `previous` had for them. `countingLines` is for a
    /// read whose counts are on screen: it counts the ones that are new or have changed size.
    package static func read(
        in directory: URL, after previous: RepoStatus = RepoStatus(), countingLines: Bool = true
    ) async -> RepoStatus? {
        guard let status = await GitClient.status(in: directory) else { return nil }
        // Before the first commit there is no HEAD to diff against: every file is untracked,
        // and a file already staged is listed nowhere until something is committed.
        let tracked = await status.oid == nil ? [] : GitClient.numstat(in: directory)
        let head = await status.oid == previous.oid ? previous.head : GitClient.head(in: directory)
        let known = Dictionary(
            previous.changes.filter(\.untracked).map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let untracked = status.untracked.map { path in
            let change = known[path] ?? FileChange(path: path, added: 0, removed: 0, untracked: true)
            return countingLines ? change.countingLines(in: directory) : change
        }
        return RepoStatus(
            changes: (tracked + untracked).sorted { $0.path < $1.path }, head: head, branch: status.branch,
            oid: status.oid)
    }
}

extension FileChange {
    /// Over this, an untracked file is never opened to count its lines and shows as a new file:
    /// a bundle or log an agent left in the tree would otherwise be read whole on every refresh.
    static let countLimit = 1 << 20

    /// This untracked file with its lines counted, or itself when its size is still the size
    /// it was counted at, which costs a `stat` and no read.
    ///
    /// ponytail: keyed on size alone, so a rewrite to exactly the same size keeps its old
    /// count until the size moves. Add the modification date to the key if that shows.
    func countingLines(in directory: URL) -> FileChange {
        let file = directory.appendingPathComponent(path).path
        var info = stat()
        let size = stat(file, &info) == 0 ? Int(info.st_size) : 0
        guard size != bytes else { return self }
        // Lines as the review has always counted them: blank ones don't count, and a file that
        // isn't UTF-8 text counts none.
        let lines =
            size > Self.countLimit
            ? 0 : (try? String(contentsOfFile: file, encoding: .utf8))?.split(separator: "\n").count ?? 0
        return FileChange(path: path, added: lines, removed: 0, untracked: true, bytes: size)
    }
}
