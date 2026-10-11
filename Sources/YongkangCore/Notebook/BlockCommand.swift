import Foundation

/// A command a block asks the user to run themselves, with what it would run, read from disk
/// by the app rather than described by the agent.
///
/// An agent whose sandbox refused to move branches wrote a script to its scratch folder and
/// asked for `! bash <path>`: one line, and the user saw nothing of what it would do — nor the
/// second script it called, nor the program it had downloaded beside them. An agent's account
/// of its own script is what is being checked, so the pane beside the session shows the files
/// themselves, and the agent's explanation stays in its reply, where the two can be compared.
package struct BlockCommand: Equatable, Sendable {
    package let line: String
    /// Every file the command names, then every script a shown script names beside itself.
    package let files: [File]
    /// Lines worth reading twice, grouped by what they do. A pattern match, never a verdict:
    /// a line spelt differently is missed, and nothing flagged is not the same as safe.
    package let flags: [Flag]
    /// More files were named than `fileLimit` lets the pane show. Never quietly: the ones past
    /// the limit run all the same.
    package let truncated: Bool

    package struct File: Equatable, Sendable, Identifiable {
        package var id: String { url.path }
        package let url: URL
        /// The file whose text named it; nil when the command itself does.
        package let namedBy: String?
        package let content: Content
        package let modified: Date?
    }

    package enum Content: Equatable, Sendable {
        case text(String)
        /// The command names a script that is not there, or not yet.
        case missing
        case binary(bytes: Int)
        case tooLarge(bytes: Int)
        /// Data named like a key or a token. A secret on screen is a secret in the next
        /// screenshot. A script is never this, whatever its name: it is what runs.
        case secret
    }

    package struct Flag: Equatable, Sendable, Identifiable {
        package var id: Kind { kind }
        package let kind: Kind
        package let places: [Place]
    }

    /// A line of a shown file, or of the command itself when `file` is nil.
    package struct Place: Equatable, Sendable {
        package let file: URL?
        package let line: Int
    }

    package enum Kind: CaseIterable, Sendable {
        case hidden, network, history, remote, discards, deletes, admin, path, fetchedCode, secrets, settings

        package var label: String {
            switch self {
            case .hidden: "Has characters that show differently than they run"
            case .network: "Talks to a server"
            case .history: "Rewrites git history or branches"
            case .remote: "Changes a git remote"
            case .discards: "Can discard uncommitted work"
            case .deletes: "Deletes files"
            case .admin: "Runs as administrator"
            case .path: "Changes where programs are found"
            case .fetchedCode: "Runs code it fetches or builds"
            case .secrets: "Reads or stores a secret"
            case .settings: "Changes system or global settings"
            }
        }

        // ponytail: a short list of spellings. One that reads a shell's grammar is the upgrade
        // if agents keep writing what this misses.
        var pattern: String {
            switch self {
            case .hidden: Self.hiddenCharacters
            case .network: #"\bgit\s+push\b|\b(curl|wget|scp|rsync|ssh|gh)\s|\bnpm\s+publish\b"#
            case .history:
                #"filter-repo|filter-branch|\bupdate-ref\b|\brebase\b|\bbranch\s+-D\b|\bpush\b.*\s(--force|-f)\b"#
            case .remote: #"\bremote\s+(add|remove|rm|set-url|rename)\b"#
            case .discards:
                #"\breset\s+--hard\b|\brestore\b(?!.*--staged\s+--\s)|\bcheckout\s+--\s|\bclean\s+-\w*f|\bstash\s+(drop|clear)\b"#
            case .deletes: #"\brm\s|\brmdir\s|\bgh\s+repo\s+delete\b"#
            case .admin: #"\bsudo\b"#
            case .path: #"\bPATH="#
            case .fetchedCode: #"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python3?)\b|\beval\b"#
            case .secrets: #"\bsecurity\s+(find|add|delete)-|\bsecret\s+set\b|generate_keys|\bkeychain\b"#
            case .settings: #"\bdefaults\s+write\b|\bconfig\s+--global\b|\blaunchctl\b|\bchmod\b|\bchown\b|>>?\s*~/\."#
            }
        }

        /// What a terminal would not show as itself: bidi overrides that reorder a line, zero-width
        /// and other format characters, line separators a shell does not break on, and control
        /// characters other than a tab. The shell runs them; the pane has to show they are there.
        static let hiddenCharacters = #"[\p{Cf}\p{Zl}\p{Zp}\x{0}-\x{8}\x{B}-\x{1F}\x{7F}-\x{9F}]"#
    }

    /// What `line` runs, read from disk now. Relative paths are the project folder's, where the
    /// session the command is pasted into runs.
    ///
    /// Every call finds and reads the files again — a date says nothing about a file that did
    /// not exist last time, or one rewritten with its old date put back. Only the line matching
    /// is skipped, when `previous` read exactly these files with exactly this text.
    package static func read(_ line: String, in directory: URL, reusing previous: BlockCommand? = nil) -> BlockCommand {
        let (files, truncated) = discover(line, in: directory)
        if let previous, previous.line == line, previous.files == files, previous.truncated == truncated {
            return previous
        }
        return BlockCommand(line: line, files: files, flags: flags(line, files), truncated: truncated)
    }

    /// `text` with every character `hiddenCharacters` matches written out as `⟨U+202E⟩`, so the
    /// pane draws a line the way it runs rather than the way a bidi override reorders it.
    package static func visible(_ text: String) -> String {
        guard let pattern = try? NSRegularExpression(pattern: Kind.hiddenCharacters),
            pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        else { return text }
        return text.unicodeScalars.map { scalar in
            let one = String(scalar)
            guard scalar != "\t",
                pattern.firstMatch(in: one, range: NSRange(one.startIndex..., in: one)) != nil
            else { return one }
            return "⟨U+" + String(format: "%04X", scalar.value) + "⟩"
        }
        .joined()
    }

    // MARK: - Finding the files

    // ponytail: a dozen files, half a megabyte each. Past that the pane says so rather than
    // drawing it; raise these if a real command needs more.
    package static let fileLimit = 12
    static let byteLimit = 512 * 1024

    private static let scriptExtensions: Set<String> = [
        "sh", "bash", "zsh", "fish", "command", "py", "rb", "pl", "js", "mjs", "cjs", "ts", "swift", "applescript",
    ]

    /// The command's own files first, in the order it names them, then each script that a shown
    /// script names beside itself, breadth first.
    private static func discover(_ line: String, in directory: URL) -> (files: [File], truncated: Bool) {
        var found: [File] = []
        var seen: Set<String> = []
        var queue: [(url: URL, namedBy: String?)] = named(byCommand: line, in: directory).map { ($0, nil) }
        while !queue.isEmpty, found.count < fileLimit {
            let next = queue.removeFirst()
            guard seen.insert(next.url.path).inserted else { continue }
            let (content, modified) = read(next.url)
            found.append(File(url: next.url, namedBy: next.namedBy, content: content, modified: modified))
            if case .text(let text) = content {
                queue += named(in: text, beside: next.url).map { ($0, next.url.lastPathComponent) }
            }
        }
        return (found, queue.contains { !seen.contains($0.url.path) })
    }

    /// Each word of the command that is a file, or that is a script's name with nothing there.
    static func named(byCommand line: String, in directory: URL) -> [URL] {
        line.components(separatedBy: CharacterSet(charactersIn: " \t\n;|&<>()`="))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-") }
            .compactMap { word in
                let url = path(word, in: directory)
                var folder: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &folder)
                if exists { return folder.boolValue ? nil : url }
                return scriptExtensions.contains(url.pathExtension.lowercased()) ? url : nil
            }
    }

    /// The scripts in `file`'s folder that its text names — `"$S/rewrite.sh"` — and the
    /// programs in a folder it names, which a script reaches by bare name once it puts that
    /// folder on `PATH`. A name that only looks like one shows an extra file, which is the
    /// direction to be wrong in.
    static func named(in text: String, beside file: URL) -> [URL] {
        let folder = file.deletingLastPathComponent()
        return children(of: folder).flatMap { url -> [URL] in
            let name = url.lastPathComponent
            guard url.path != file.path else { return [] }
            if isFolder(url) {
                return text.contains("/" + name) ? children(of: url).filter { !isFolder($0) && isScript($0) } : []
            }
            return text.contains(name) && isScript(url) ? [url] : []
        }
    }

    private static func path(_ word: String, in directory: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var expanded = word
        if expanded == "~" || expanded.hasPrefix("~/") { expanded = home + expanded.dropFirst() }
        if expanded.hasPrefix("$HOME") { expanded = home + expanded.dropFirst(5) }
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : directory.appendingPathComponent(expanded)
        return url.standardizedFileURL
    }

    private static func children(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().map { folder.appendingPathComponent($0) }
    }

    private static func isFolder(_ url: URL) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue
    }

    /// A script by its extension, its execute bit or its `#!` — what a shell would run.
    private static func isScript(_ url: URL) -> Bool {
        if scriptExtensions.contains(url.pathExtension.lowercased()) { return true }
        if FileManager.default.isExecutableFile(atPath: url.path) { return true }
        let handle = try? FileHandle(forReadingFrom: url)
        defer { try? handle?.close() }
        return (try? handle?.read(upToCount: 2)) == Data("#!".utf8)
    }

    private static func read(_ url: URL) -> (Content, Date?) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return (.missing, nil)
        }
        let size = (attributes[.size] as? Int) ?? 0
        let modified = attributes[.modificationDate] as? Date
        if looksSecret(url), !isScript(url) { return (.secret, modified) }
        if size > byteLimit { return (.tooLarge(bytes: size), modified) }
        guard let data = try? Data(contentsOf: url), !data.contains(0),
            let text = String(data: data, encoding: .utf8)
        else { return (.binary(bytes: size), modified) }
        return (.text(text), modified)
    }

    private static func looksSecret(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let words = ["secret", "token", "credential", "password", ".env", "id_rsa", "id_ed25519", "id_ecdsa"]
        let extensions: Set<String> = ["key", "pem", "p12", "p8", "pfx", "keychain"]
        return words.contains { name.contains($0) } || extensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Flags

    private static func flags(_ line: String, _ files: [File]) -> [Flag] {
        var lines: [(Place, String)] = line.components(separatedBy: "\n").enumerated()
            .map { (Place(file: nil, line: $0.offset + 1), $0.element) }
        for file in files {
            guard case .text(let text) = file.content else { continue }
            lines += text.components(separatedBy: "\n").enumerated()
                .map { (Place(file: file.url, line: $0.offset + 1), $0.element) }
        }
        // A comment says what a line is for; only what runs is matched. A hidden character is
        // looked for everywhere, since what it hides may be that a line is not a comment at all.
        let code = lines.filter { !$0.1.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        return Kind.allCases.compactMap { kind in
            guard let pattern = try? NSRegularExpression(pattern: kind.pattern) else { return nil }
            let places = (kind == .hidden ? lines : code).filter { _, text in
                pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }.map(\.0)
            return places.isEmpty ? nil : Flag(kind: kind, places: places)
        }
    }

    /// The lines of `file` that a flag points at, for the pane to mark.
    package func flagged(_ file: URL) -> Set<Int> {
        Set(flags.flatMap(\.places).filter { $0.file?.path == file.path }.map(\.line))
    }
}
