import Foundation

/// One word of a command line, as a POSIX shell would hand it to the program.
package struct ShellWord: Equatable, Sendable {
    package let text: String
    /// The shell would still rewrite it before using it — `$S/x.sh`, `*.sh`, `$(…)` — so what
    /// it names is only known when it runs. Only `~` and `$HOME` are filled in here.
    package let expands: Bool
    /// The first word of a command: the program the shell looks up on `PATH`.
    package let isCommand: Bool
}

/// A command line split the way a shell splits it, closely enough to say which files it names.
///
/// Splitting on spaces showed a different file than the shell would run: `"/tmp/my dir/x.sh"`
/// became `/tmp/my` and `dir/x.sh`, and a `dir/x.sh` in the project folder was drawn as the
/// script. Quotes and backslashes are honoured here, and a word the shell would still rewrite
/// says so instead of being guessed at.
///
/// ponytail: quotes, escapes, operators, `~`, `$HOME` and command position — not arrays, here
/// documents or `case`. A `run:` is one line the agent was told to keep plain; a word this gets
/// wrong is shown as one the shell rewrites, never as a different file.
enum ShellWords {
    /// Programs that run the word after them, so that word is a command too.
    private static let wrappers: Set<String> = [
        "sudo", "env", "exec", "nohup", "time", "command", "builtin", "xargs", "nice", "caffeinate",
    ]

    static func split(_ line: String, home: String) -> [ShellWord] {
        var state = State(chars: Array(line), home: home)
        while state.index < state.chars.count, state.step() {}
        state.end()
        return state.words
    }

    private struct State {
        let chars: [Character]
        let home: String
        var index = 0
        var words: [ShellWord] = []
        var text = ""
        /// A word is open — even `""`, which is a word with nothing in it.
        var open = false
        var expands = false
        var commandNext = true
        var quote: Character?

        /// One character, or an escape, or a `$HOME`. False at a comment, which ends the line.
        mutating func step() -> Bool {
            let c = chars[index]
            switch quote {
            case "'"?:
                if c == "'" { quote = nil } else { text.append(c) }
                index += 1
            case "\""?:
                inDouble(c)
            default:
                if c == "#", !open { return false }
                outside(c)
            }
            return true
        }

        private mutating func inDouble(_ c: Character) {
            if c == "\"" {
                quote = nil
                index += 1
            } else if c == "\\", let next = peek(1), "$`\"\\".contains(next) {
                text.append(next)
                index += 2
            } else if c == "$" {
                dollar()
            } else {
                if c == "`" { expands = true }
                text.append(c)
                index += 1
            }
        }

        private mutating func outside(_ c: Character) {
            if c == " " || c == "\t" {
                end()
                index += 1
            } else if c == "\n" || ";|&()<>".contains(c) {
                end()
                // What follows `<` or `>` is a file; what follows the rest is a new command.
                if c != "<", c != ">" { commandNext = true }
                index += 1
            } else if c == "\\" {
                open = true
                if let next = peek(1), next != "\n" { text.append(next) }
                index += 2
            } else if c == "'" || c == "\"" {
                open = true
                quote = c
                index += 1
            } else if c == "$" {
                open = true
                dollar()
            } else if c == "~", !open, peek(1).map({ $0 == "/" || $0 == " " }) ?? true {
                open = true
                text += home
                index += 1
            } else {
                // `~other` is another user's folder: the shell's to fill in, not ours.
                if "*?[`{".contains(c) || (c == "~" && !open) { expands = true }
                open = true
                text.append(c)
                index += 1
            }
        }

        /// `$HOME` and `${HOME}` are the one variable worth filling in: it is how a path to the
        /// user's own folder is written. Anything else is left for the shell, and said to be.
        private mutating func dollar() {
            let rest = String(chars[(index + 1)...].prefix(6))
            if rest.hasPrefix("{HOME}") {
                text += home
                index += 7
            } else if rest.hasPrefix("HOME"), !(peek(5).map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false) {
                text += home
                index += 5
            } else {
                expands = true
                text.append("$")
                index += 1
            }
        }

        mutating func end() {
            guard open else { return }
            let assignment =
                commandNext && text.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil
            let option = commandNext && text.hasPrefix("-")
            words.append(ShellWord(text: text, expands: expands, isCommand: commandNext && !assignment && !option))
            if !assignment, !option { commandNext = !expands && ShellWords.wrappers.contains(text) }
            text = ""
            open = false
            expands = false
        }

        private func peek(_ offset: Int) -> Character? {
            index + offset < chars.count ? chars[index + offset] : nil
        }
    }
}
