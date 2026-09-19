import Foundation

/// One file an agent touched, as git sees it.
package struct FileChange: Identifiable, Equatable, Sendable {
    package var id: String { path }
    package let path: String
    package let added: Int
    package let removed: Int
    /// A file git has never seen — written by an agent this session, with nothing to diff
    /// against, so it is listed as whole-file new rather than shown as a fake hunk.
    package let untracked: Bool
    /// An untracked file's size when its lines were last counted, and nil until they are.
    /// git doesn't count lines in a file it has never seen, so `RepoStatus.read` opens it.
    var bytes: Int? = nil

    /// False for an untracked file whose lines are not counted — over `countLimit`, or not
    /// counted yet — so a screen says "new file" rather than a +0 it doesn't know.
    package var counted: Bool { !untracked || (bytes ?? .max) <= Self.countLimit }

    package var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }

    /// Spelled out for the shots, which draw a finished task's files without a repo to read.
    package init(path: String, added: Int, removed: Int, untracked: Bool, bytes: Int? = nil) {
        self.path = path
        self.added = added
        self.removed = removed
        self.untracked = untracked
        self.bytes = bytes
    }
}

/// One row of a unified diff.
package struct DiffLine: Identifiable {
    package enum Kind { case hunk, add, remove, context }
    package let id = UUID()
    package let kind: Kind
    package let old: String
    package let new: String
    package let text: String
}

/// What the agents actually changed, read straight from `git` in the project folder. No
/// library and no index of our own: the repo already knows, and shelling out to the same
/// command a person would type means the review pane can never disagree with the terminal
/// sitting next to it.
///
/// Everything is against `HEAD`, so a review shows the work as it stands — uncommitted,
/// because no agent commits, which is the moment this pane exists for.
///
/// Every call is `async` and runs git through `AsyncProcess`, so a slow repo costs a wait and
/// never a frozen window.
package enum GitClient {
    /// The part of `git status` a refresh needs: the commit and branch the tree is on, and the
    /// files git has never seen. Tracked changes come from `numstat`, which also counts them.
    struct Status: Equatable {
        /// Nil before the first commit, which is `(initial)`.
        var oid: String?
        /// Nil on a detached HEAD, which has no branch to name.
        var branch: String?
        var untracked: [String] = []
    }

    /// Nil when `directory` is not in a repository, which is also the only check a refresh
    /// makes for that.
    ///
    /// `--no-optional-locks`, because a plain `git status` refreshes the index and writes it
    /// back, taking `index.lock` while it does: polled every few seconds beside agents that run
    /// git themselves, that is an agent's `git add` failing on a lock the app holds.
    /// `--untracked-files=all` lists each file in a new folder rather than the folder, which is
    /// what a task's recorded paths are matched against.
    static func status(in directory: URL) async -> Status? {
        guard
            let output = await git(
                ["--no-optional-locks", "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"],
                in: directory)
        else { return nil }
        guard output.status == 0 else {
            // 128 is "not a git repository", which `ProjectReader.repo` answers by creating one
            // and which is otherwise just a folder nobody has made a repo — not news, and it
            // would be news on every refresh. Anything else is a repo git cannot read, which
            // shows as an empty Review screen. Never git's own words: they quote the user's
            // paths and branch names, and the status says enough.
            if output.status != 128 {
                Log.git.notice(
                    "git status in \(directory.path, privacy: .public) exited \(output.status, privacy: .public)")
            }
            return nil
        }
        return parseStatus(output.stdout)
    }

    /// Every tracked file that differs from `HEAD`, staged or not, with its line counts. Only
    /// meaningful once there is a `HEAD`; before the first commit git refuses, and nothing is
    /// listed.
    static func numstat(in directory: URL) async -> [FileChange] {
        guard let output = await git(["diff", "--numstat", "-z", "HEAD"], in: directory), output.status == 0 else {
            return []
        }
        return parseNumstat(output.stdout)
    }

    /// The commit a review is standing on, as `<short sha> <subject>`, so the pane can say what
    /// it is diffing against. `status` already gives its id; this is the one extra call, and
    /// `RepoStatus.read` only makes it when that id changes.
    static func head(in directory: URL) async -> String? {
        let text = await git(["log", "-1", "--format=%h %s"], in: directory)?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// The unified diff of one file, already split into rows with their line numbers so the
    /// view only has to draw them.
    package static func diff(of change: FileChange, in directory: URL) async -> [DiffLine] {
        guard !change.untracked else { return newFileLines(change, in: directory) }
        let text = await git(["diff", "--unified=3", "HEAD", "--", change.path], in: directory)?.text ?? ""
        var lines: [DiffLine] = []
        var old = 0
        var new = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                (old, new) = hunkStart(line)
                lines.append(DiffLine(kind: .hunk, old: "", new: "", text: line))
            } else if lines.isEmpty {
                continue  // the file header, which the pane draws itself
            } else if line.hasPrefix("+") {
                lines.append(DiffLine(kind: .add, old: "", new: "\(new)", text: String(line.dropFirst())))
                new += 1
            } else if line.hasPrefix("-") {
                lines.append(DiffLine(kind: .remove, old: "\(old)", new: "", text: String(line.dropFirst())))
                old += 1
            } else if line.hasPrefix(" ") {
                lines.append(
                    DiffLine(
                        kind: .context, old: "\(old)", new: "\(new)",
                        text: String(line.dropFirst())))
                old += 1
                new += 1
            }
        }
        return lines
    }

    /// Commit — the one write this app makes to a user's repo, and only from a button on
    /// the review screen. With `paths` it is one approved task: only those files are staged
    /// and committed, and whatever else sits in the index or the tree is left exactly as it
    /// was. Without, everything. Returns git's own words on failure and nil on success.
    /// Pushing and merging stay the user's.
    package static func commit(message: String, paths: [String]? = nil, in directory: URL) async -> String? {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "A commit needs a message." }
        guard paths?.isEmpty != true else { return "This task has no changed files left to commit." }
        guard await isRepository(directory) else { return "\(directory.lastPathComponent) is not a git repository." }
        let steps =
            paths.map { [["add", "--"] + $0, ["commit", "--message", text, "--"] + $0] }
            ?? [["add", "--all"], ["commit", "--message", text]]
        for arguments in steps {
            let result = await execute(arguments, in: directory)
            guard result.status != 0 else { continue }
            let said = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return said.isEmpty ? "git \(arguments[0]) failed (\(result.status))." : said
        }
        return nil
    }

    /// `git init`, so agents' work has a baseline to diff against and approving has somewhere
    /// to commit. Creates the repository only — nothing is staged or committed. Returns git's
    /// own words on failure.
    package static func initialize(in directory: URL) async -> String? {
        let result = await execute(["init"], in: directory)
        return result.status == 0 ? nil : result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing

    /// `git status --porcelain=v2 --branch -z`: `# branch.*` headers, then one NUL-terminated
    /// record per file. Paths are raw bytes with nothing quoted, so a space or a newline in a
    /// name is just part of it.
    static func parseStatus(_ output: Data) -> Status {
        var status = Status()
        var records = output.split(separator: 0, omittingEmptySubsequences: false).makeIterator()
        while let record = records.next() {
            if let oid = record.value(after: "# branch.oid ") {
                status.oid = oid == "(initial)" ? nil : oid
            } else if let head = record.value(after: "# branch.head ") {
                status.branch = head == "(detached)" ? nil : head
            } else if let path = record.value(after: "? ") {
                status.untracked.append(path)
            } else if record.value(after: "2 ") != nil {
                // A rename or copy: the original path is the next NUL-separated record, not a
                // record of its own. `1` and `u` records carry one path and need nothing.
                _ = records.next()
            }
        }
        return status
    }

    /// `git diff --numstat -z`: `<added>\t<removed>\t<path>` per file, NUL-terminated. A rename
    /// leaves the path empty and gives the old and new paths as the next two records, and a
    /// binary file counts `-` for both.
    static func parseNumstat(_ output: Data) -> [FileChange] {
        var changes: [String: FileChange] = [:]
        var records = output.split(separator: 0, omittingEmptySubsequences: false).makeIterator()
        while let record = records.next() {
            let fields = record.split(separator: UInt8(ascii: "\t"), maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            var path = String(decoding: fields[2], as: UTF8.self)
            if path.isEmpty {
                _ = records.next()
                path = records.next().map { String(decoding: $0, as: UTF8.self) } ?? ""
            }
            guard !path.isEmpty else { continue }
            func count(_ field: Data) -> Int { Int(String(decoding: field, as: UTF8.self)) ?? 0 }
            changes[path] = FileChange(path: path, added: count(fields[0]), removed: count(fields[1]), untracked: false)
        }
        return Array(changes.values)
    }

    /// `@@ -215,12 +215,14 @@` — the two starting line numbers.
    static func hunkStart(_ line: String) -> (Int, Int) {
        let parts = line.split(separator: " ")
        func number(_ token: Substring?) -> Int {
            guard let token else { return 0 }
            return Int(token.dropFirst().split(separator: ",").first ?? "") ?? 0
        }
        return (number(parts.first { $0.hasPrefix("-") }), number(parts.first { $0.hasPrefix("+") }))
    }

    // MARK: - Plumbing

    /// This process's environment without the variables that point git at a repository
    /// (`git rev-parse --local-env-vars`). Run from a git hook or `git rebase --exec`, an
    /// inherited `GIT_DIR` beats `currentDirectoryURL`: a test's `git init` in a temp folder
    /// once rewrote the real checkout's config to `bare = true`.
    static let environment = ProcessInfo.processInfo.environment.filter {
        ![
            "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
            "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE",
            "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX", "GIT_SHALLOW_FILE",
            "GIT_COMMON_DIR",
        ].contains($0.key)
    }

    private static func isRepository(_ directory: URL) async -> Bool {
        await git(["rev-parse", "--is-inside-work-tree"], in: directory)?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private static func newFileLines(_ change: FileChange, in directory: URL) -> [DiffLine] {
        let url = directory.appendingPathComponent(change.path)
        // git listed this file a moment ago, so anything but "it was deleted since" is worth
        // knowing: it is a row in Review that draws as an empty diff.
        guard let text = Log.contents(of: url, Log.git) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { DiffLine(kind: .add, old: "", new: "\($0.offset + 1)", text: String($0.element)) }
    }

    /// Nil when git could not be started, or the caller was cancelled.
    ///
    /// A non-zero exit is the caller's to interpret — `numstat` before the first commit is a
    /// refusal, not a fault — but git failing to *start* at all means every review screen is
    /// empty with nothing on screen to say why, so it is logged. Cancellation is not: a read
    /// the window no longer wants is the normal case, on every selection change.
    private static func git(_ arguments: [String], in directory: URL) async -> AsyncProcess.Output? {
        do {
            return try await AsyncProcess.run(
                URL(fileURLWithPath: "/usr/bin/env"), ["git"] + arguments, in: directory, environment: environment)
        } catch {
            guard !(error is CancellationError) else { return nil }
            Log.git.error(
                "git \(arguments.first ?? "", privacy: .public) in \(directory.path, privacy: .public) could not run: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// The same call, kept for the commands whose failure the user has to be told about:
    /// one pipe for both streams, because what comes back is a sentence for a person and
    /// git says most of it on stderr.
    private static func execute(_ arguments: [String], in directory: URL) async -> (status: Int32, text: String) {
        do {
            let output = try await AsyncProcess.run(
                URL(fileURLWithPath: "/usr/bin/env"), ["git"] + arguments, in: directory,
                environment: environment, stderr: .merge)
            return (output.status, output.text)
        } catch {
            return (1, "could not run git: \(error.localizedDescription)")
        }
    }
}

extension Data {
    /// The rest of the record after `prefix`, or nil when it doesn't start with it. Matched on
    /// bytes, not characters: a path that begins with a combining mark would join the space
    /// before it into one character, and a `String` prefix would no longer match.
    fileprivate func value(after prefix: String) -> String? {
        starts(with: prefix.utf8) ? String(decoding: dropFirst(prefix.utf8.count), as: UTF8.self) : nil
    }
}
