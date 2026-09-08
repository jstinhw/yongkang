import Foundation

/// One file an agent touched, as git sees it.
struct FileChange: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let added: Int
    let removed: Int
    /// A file git has never seen — written by an agent this session, with nothing to diff
    /// against, so it is listed as whole-file new rather than shown as a fake hunk.
    let untracked: Bool

    var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

/// One row of a unified diff.
struct DiffLine: Identifiable {
    enum Kind { case hunk, add, remove, context }
    let id = UUID()
    let kind: Kind
    let old: String
    let new: String
    let text: String
}

/// What the agents actually changed, read straight from `git` in the project folder. No
/// library and no index of our own: the repo already knows, and shelling out to the same
/// command a person would type means the review pane can never disagree with the terminal
/// sitting next to it.
///
/// Everything is against `HEAD`, so a review shows the work as it stands — what a lead
/// hands over before it opens a PR, which is the moment this pane exists for.
enum GitChanges {

    static func changes(in directory: URL) -> [FileChange] {
        guard isRepository(directory) else { return [] }
        var counts: [String: (Int, Int)] = [:]
        for line in run(["diff", "--numstat", "HEAD"], in: directory).split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            counts[parts[2]] = (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
        }
        let tracked = counts.map { FileChange(path: $0.key, added: $0.value.0,
                                              removed: $0.value.1, untracked: false) }
        let untracked = run(["ls-files", "--others", "--exclude-standard"], in: directory)
            .split(separator: "\n")
            .map { FileChange(path: String($0), added: lineCount(String($0), in: directory),
                              removed: 0, untracked: true) }
        return (tracked + untracked).sorted { $0.path < $1.path }
    }

    /// The unified diff of one file, already split into rows with their line numbers so the
    /// view only has to draw them.
    static func diff(of change: FileChange, in directory: URL) -> [DiffLine] {
        guard !change.untracked else { return newFileLines(change, in: directory) }
        let text = run(["diff", "--unified=3", "HEAD", "--", change.path], in: directory)
        var lines: [DiffLine] = []
        var old = 0, new = 0
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
                lines.append(DiffLine(kind: .context, old: "\(old)", new: "\(new)",
                                      text: String(line.dropFirst())))
                old += 1; new += 1
            }
        }
        return lines
    }

    /// The commit a review is standing on, so the pane can say what it is diffing against.
    static func head(in directory: URL) -> String? {
        guard isRepository(directory) else { return nil }
        let text = run(["log", "-1", "--format=%h %s"], in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func branch(in directory: URL) -> String? {
        guard isRepository(directory) else { return nil }
        let text = run(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Stage everything and commit — the one write this app makes to a user's repo, and
    /// only from the button on the review screen. Returns git's own words on failure and
    /// nil on success. Pushing and merging stay the user's.
    static func commit(message: String, in directory: URL) -> String? {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "A commit needs a message." }
        guard isRepository(directory) else { return "\(directory.lastPathComponent) is not a git repository." }
        for arguments in [["add", "--all"], ["commit", "--message", text]] {
            let result = execute(arguments, in: directory)
            guard result.status != 0 else { continue }
            let said = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return said.isEmpty ? "git \(arguments[0]) failed (\(result.status))." : said
        }
        return nil
    }

    static func isRepository(_ directory: URL) -> Bool {
        run(["rev-parse", "--is-inside-work-tree"], in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    // MARK: - Plumbing

    private static func newFileLines(_ change: FileChange, in directory: URL) -> [DiffLine] {
        let url = directory.appendingPathComponent(change.path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { DiffLine(kind: .add, old: "", new: "\($0.offset + 1)", text: String($0.element)) }
    }

    private static func lineCount(_ path: String, in directory: URL) -> Int {
        let url = directory.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
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

    private static func run(_ arguments: [String], in directory: URL) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git"] + arguments
        task.currentDirectoryURL = directory
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The same call, kept for the commands whose failure the user has to be told about:
    /// one pipe for both streams, because what comes back is a sentence for a person and
    /// git says most of it on stderr.
    private static func execute(_ arguments: [String], in directory: URL) -> (status: Int32, text: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git"] + arguments
        task.currentDirectoryURL = directory
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return (1, "could not run git: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
