import Foundation

/// One thing worth reading in a subagent's transcript.
///
/// A transcript is mostly tool calls and their output, and printing every one buries the
/// two things a person actually wants: what the agent was asked, and what it has said back.
/// Claude Code's own view collapses a run of tool work into a single line — "Searched for 1
/// pattern, read 14 files, ran 8 shell commands" — and this does the same, keeping the raw
/// lines behind it so a run can still be opened when something looks wrong.
struct TranscriptStep: Identifiable {
    enum Kind { case task, say, skill, work }

    /// Position in the list, so an opened run stays open across the 2-second reload —
    /// a fresh UUID per parse would close it again on every poll.
    let id: Int
    let kind: Kind
    /// The prose, the skill's name, or the summary line for a run of work.
    let text: String
    /// The lines a work summary stands for, shown when it is opened.
    var detail: [TranscriptLine] = []
    var errors: Int = 0
}

enum TranscriptSteps {

    static func steps(_ lines: [TranscriptLine]) -> [TranscriptStep] {
        var steps: [TranscriptStep] = []
        var run: [TranscriptLine] = []

        func flushRun() {
            guard !run.isEmpty else { return }
            let calls = run.filter { $0.label == "Tool" }
            steps.append(TranscriptStep(id: steps.count, kind: .work,
                                        text: summary(of: calls.map(\.text)),
                                        detail: run,
                                        errors: run.filter(\.isError).count))
            run = []
        }

        for line in lines {
            switch line.label {
            case "Task", "Reply":
                flushRun()
                steps.append(TranscriptStep(id: steps.count,
                                            kind: line.label == "Task" ? .task : .say,
                                            text: line.text))
            case "Tool" where toolName(line.text) == "Skill":
                // A skill is the agent picking up a role — the one tool call that says
                // something about the work rather than being the work.
                flushRun()
                steps.append(TranscriptStep(id: steps.count, kind: .skill,
                                            text: skillName(line.text)))
            default:
                run.append(line)
            }
        }
        flushRun()
        return steps
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
            .map { $0.offset == 0 ? $0.element.prefix(1).uppercased() + $0.element.dropFirst()
                                  : $0.element }
            .joined(separator: ", ")
    }

    private static let order = ["search", "read", "list", "edit", "write", "run",
                                "fetch", "spawn", "note", "other"]

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

    /// `Skill(command: qa-dev, …)` → `Skill(qa-dev)`, which is how Claude Code names it.
    static func skillName(_ call: String) -> String {
        guard let open = call.firstIndex(of: "("), let close = call.lastIndex(of: ")"),
              open < close else { return call }
        let arguments = call[call.index(after: open)..<close]
        let value = arguments.split(separator: ",").first.map { part -> String in
            let field = part.split(separator: ":", maxSplits: 1)
            return String(field.count == 2 ? field[1] : field[0])
        }
        let name = (value ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Skill" : "Skill(\(name))"
    }
}
