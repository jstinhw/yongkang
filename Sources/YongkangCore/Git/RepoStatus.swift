import Foundation

/// What git said about a project's working tree at the last read: the changes under review
/// and the commit and branch they sit on. Replaced whole, like `NotebookSnapshot`.
package struct RepoStatus: Equatable {
    package let changes: [FileChange]
    package let head: String?
    package let branch: String?

    package init(changes: [FileChange] = [], head: String? = nil, branch: String? = nil) {
        self.changes = changes
        self.head = head
        self.branch = branch
    }

    package static func read(in directory: URL) -> RepoStatus {
        RepoStatus(
            changes: GitChanges.changes(in: directory),
            head: GitChanges.head(in: directory),
            branch: GitChanges.branch(in: directory))
    }
}
