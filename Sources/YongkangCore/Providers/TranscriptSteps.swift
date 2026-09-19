import Foundation

/// One thing worth reading in a subagent's transcript.
///
/// A transcript is mostly tool calls and their output, and printing every one buries the
/// two things a person actually wants: what the agent was asked, and what it has said back.
/// Claude Code's own view collapses a run of tool work into a single line — "Searched for 1
/// pattern, read 14 files, ran 8 shell commands" — and this does the same, keeping the raw
/// lines behind it so a run can still be opened when something looks wrong.
package struct TranscriptStep: Identifiable {
    package enum Kind { case task, say, skill, note, work }

    /// Position in the list, so an opened run stays open across the 2-second reload —
    /// a fresh UUID per parse would close it again on every poll.
    package let id: Int
    package let kind: Kind
    /// The prose, the skill's name, or the summary line for a run of work.
    package let text: String
    /// The lines a work summary stands for, shown when it is opened.
    package var detail: [TranscriptLine] = []
    package var errors: Int = 0
}

package enum TranscriptSteps {

    package static func steps(_ lines: [TranscriptLine]) -> [TranscriptStep] {
        var steps: [TranscriptStep] = []
        var run: [TranscriptLine] = []
        /// A subagent is briefed once. Every later user message is either the harness
        /// talking to the model or the lead talking to the agent, and only one of those
        /// was written for a person to read.
        var briefed = false

        func flushRun() {
            let calls = run.filter { $0.label == "Tool" }
            // Results with no call in front of them are the tail of a run that has already
            // been summarised — a skill's "Launching skill: designer", most often. There is
            // nothing to say about them, so they do not get a line of their own.
            guard !calls.isEmpty else {
                run = []
                return
            }
            steps.append(
                TranscriptStep(
                    id: steps.count, kind: .work,
                    text: summary(of: calls.map(\.text)),
                    detail: run,
                    errors: run.filter(\.isError).count))
            run = []
        }

        for line in lines {
            switch line.label {
            case "Reply":
                flushRun()
                steps.append(TranscriptStep(id: steps.count, kind: .say, text: line.text))
            case "Task":
                // A dropped injection must not break the run around it in two, or the skill
                // text leaves a seam behind: "read 1 file" and then "read 13 files".
                if !briefed {
                    flushRun()
                    briefed = true
                    steps.append(TranscriptStep(id: steps.count, kind: .task, text: line.text))
                } else if let note = aside(line.text) {
                    flushRun()
                    steps.append(TranscriptStep(id: steps.count, kind: .note, text: note))
                }
            case "Tool" where toolName(line.text) == "Skill":
                // A skill is the agent picking up a role — the one tool call that says
                // something about the work rather than being the work.
                flushRun()
                steps.append(
                    TranscriptStep(
                        id: steps.count, kind: .skill,
                        text: skillName(line.text)))
            default:
                run.append(line)
            }
        }
        flushRun()
        return steps
    }

    /// What a user message after the brief is worth showing, or nil when it is the harness
    /// rather than a person. Invoking a skill pastes the whole skill document in as a user
    /// message; so do system notifications and an MCP server's instructions. None of that
    /// is news — the `Skill(designer)` line above it already says what happened, and the
    /// document behind it is context the agent was given, not something it did.
    ///
    /// Anything else is kept: a message the lead sent mid-flight is the second most
    /// interesting thing in the file, so the default is to show, not to hide.
    static func aside(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("Base directory for this skill:") { return nil }
        if trimmed.hasPrefix("[SYSTEM NOTIFICATION") { return nil }
        if trimmed.contains("<system-reminder>") { return nil }
        // A long document opening on a heading is a pasted instruction set, never a note.
        if trimmed.hasPrefix("# ") && trimmed.count > 400 { return nil }
        return trimmed
    }

    /// "Searched for 1 pattern, read 14 files, ran 8 shell commands" — the same shape Claude
    /// Code prints, in a fixed order so the line reads the same way every time.
    static func summary(of calls: [String]) -> String {
        var counts: [String: Int] = [:]
        for call in calls { counts[verb(for: toolName(call)), default: 0] += 1 }
        let phrases = order.compactMap { verb -> String? in
            guard let count = counts[verb], count > 0 else { return nil }
            return phrase(verb, count)
        }
        guard !phrases.isEmpty else { return "Worked" }
        return phrases.enumerated()
            .map {
                $0.offset == 0
                    ? $0.element.prefix(1).uppercased() + $0.element.dropFirst()
                    : $0.element
            }
            .joined(separator: ", ")
    }

    private static let order = [
        "search", "read", "list", "edit", "write", "run",
        "fetch", "spawn", "note", "other",
    ]

    private static func verb(for tool: String) -> String {
        switch tool {
        case "Grep", "Glob", "WebSearch": return "search"
        case "Read", "NotebookRead": return "read"
        case "LS", "ListDir": return "list"
        case "Edit", "MultiEdit", "NotebookEdit": return "edit"
        case "Write": return "write"
        case "Bash", "BashOutput", "shell", "local_shell": return "run"
        case "WebFetch": return "fetch"
        case "Task", "Agent", "SendMessage": return "spawn"
        case "TodoWrite": return "note"
        default: return "other"
        }
    }

    private static func phrase(_ verb: String, _ count: Int) -> String {
        let plural = count == 1 ? "" : "s"
        switch verb {
        case "search": return "searched for \(count) pattern\(plural)"
        case "read": return "read \(count) file\(plural)"
        case "list": return "listed \(count) director\(count == 1 ? "y" : "ies")"
        case "edit": return "edited \(count) file\(plural)"
        case "write": return "wrote \(count) file\(plural)"
        case "run": return "ran \(count) shell command\(plural)"
        case "fetch": return "fetched \(count) page\(plural)"
        case "spawn": return "spawned \(count) agent\(plural)"
        case "note": return "updated its plan"
        default: return "used \(count) tool\(plural)"
        }
    }

    /// `Read(file_path: …)` → `Read`. Both providers format a call this way.
    static func toolName(_ call: String) -> String {
        String(call.prefix(while: { $0 != "(" })).trimmingCharacters(in: .whitespaces)
    }

    /// `Skill(args: …, skill: designer)` → `Skill(designer)`, which is how Claude Code names it.
    /// The field is looked up by name rather than taken as the first one: a call's arguments
    /// arrive alphabetised, so `args` usually sits in front of the name and reading position
    /// one names the agent after its task.
    static func skillName(_ call: String) -> String {
        guard let open = call.firstIndex(of: "("), let close = call.lastIndex(of: ")"),
            open < close
        else { return call }
        let fields = call[call.index(after: open)..<close].components(separatedBy: ", ")
            .map { field -> (key: String, value: String) in
                let parts = field.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { return ("", field.trimmingCharacters(in: .whitespaces)) }
                return (
                    parts[0].trimmingCharacters(in: .whitespaces),
                    parts[1].trimmingCharacters(in: .whitespaces)
                )
            }
        let named = fields.first { ["skill", "command", "name"].contains($0.key) }
        let name = (named ?? fields.first)?.value ?? ""
        return name.isEmpty ? "Skill" : "Skill(\(name))"
    }
}
