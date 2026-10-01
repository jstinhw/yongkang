import Foundation

/// What a running agent last did and how much it has read, from its transcript. The board's
/// setup card shows it, so reading a large project looks like progress rather than a stall.
package struct AgentActivity: Equatable, Sendable {
    /// Every file it opened to read, re-reads included. Zero for a CLI that reads through its
    /// shell, as Codex does: there is nothing in a `cat` to count.
    package var filesRead = 0
    /// Its last tool call as a verb and what it was aimed at: "Read", "Sources/App.swift".
    package var verb: String?
    package var target: String?

    package init(filesRead: Int = 0, verb: String? = nil, target: String? = nil) {
        self.filesRead = filesRead
        self.verb = verb
        self.target = target
    }

    package init(lines: [TranscriptLine], in directory: URL) {
        let calls = lines.filter { $0.label == "Tool" }.map(\.text)
        filesRead = calls.filter { TranscriptSteps.verb(for: TranscriptSteps.toolName($0)) == "read" }.count
        guard let last = calls.last else { return }
        let tool = TranscriptSteps.toolName(last)
        verb = Self.verbs[TranscriptSteps.verb(for: tool)] ?? tool
        target = Self.target(of: last, in: directory)
    }

    private static let verbs = [
        "search": "Search", "read": "Read", "list": "List", "edit": "Edit", "write": "Write",
        "run": "Run", "fetch": "Fetch", "spawn": "Agent", "note": "Plan",
    ]

    /// The argument a person would name the call by. A call reads `Read(file_path: /a/b, limit: 5)`
    /// with its fields in alphabetical order, so each is found by name, and its value runs to the
    /// next field. A path inside the project is shown from the project's folder.
    ///
    /// ponytail: a value holding ", " (a shell command, usually) is cut there. It is one line of
    /// glimpse, not a record; read the field's JSON in the provider if it ever has to be whole.
    static func target(of call: String, in directory: URL) -> String? {
        for key in ["file_path", "pattern", "path", "command", "url"] {
            guard let field = ["(\(key): ", ", \(key): "].lazy.compactMap({ call.range(of: $0) }).first else {
                continue
            }
            var value = Substring(call[field.upperBound...].prefix { $0 != "\n" })
            if let next = value.range(of: ", ") { value = value[..<next.lowerBound] }
            if value.hasSuffix(")") { value = value.dropLast() }
            for root in [directory.path, directory.resolvingSymlinksInPath().path] {
                if value.hasPrefix(root + "/") { value = value.dropFirst(root.count + 1) }
            }
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }
}
