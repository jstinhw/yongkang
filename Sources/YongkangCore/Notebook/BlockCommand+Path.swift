import Foundation

/// The programs a command runs by bare name, looked up the way the shell it is pasted into
/// would look them up.
///
/// The first version stopped at the first match on this app's own `PATH`. An app opened from
/// the Finder has a short one, so `git` was `/usr/bin/git`, a system program, and nothing to
/// show — while the session's shell, whose `PATH` puts `~/.local/bin` first, would have run a
/// `git` script an agent left there. Now every folder is searched, the shell's own first, and
/// every match is listed.
extension BlockCommand {
    /// A program the command runs by name, and every executable by that name on the `PATH`.
    package struct Program: Equatable, Sendable, Identifiable {
        package var id: String { name }
        package let name: String
        /// In the order the folders are searched, so the first is the one a shell with that
        /// `PATH` runs. More than one means another `PATH` order runs another program.
        package let found: [URL]
    }

    /// The system's own folders, which only an installer with an administrator's password
    /// writes to. A match outside them could have been put there by anyone, an agent included.
    static let systemFolders = ["/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/System/"]

    /// The `PATH` of the shell a session runs in, the one `!` uses — which is not this app's.
    /// Nil when the shell could not be run. Printed behind a marker, as `AgentKind.installed`
    /// does, so whatever the user's rc files print on the way in is not read as a folder.
    package static func loginPath(shell: [String] = ["/bin/zsh", "-ilc"]) async -> [String]? {
        let marker = "yongkang-path:"
        guard
            let output = try? await AsyncProcess.run(
                URL(fileURLWithPath: shell[0]), Array(shell.dropFirst()) + ["printf '\(marker)%s\\n' \"$PATH\""])
        else { return nil }
        return output.text.split(whereSeparator: \.isNewline).first { $0.hasPrefix(marker) }
            .map { $0.dropFirst(marker.count).split(separator: ":").map(String.init) }
    }

    /// Where a bare command name is looked for: the login shell's folders first, since that is
    /// where the command runs, then this app's, then the usual install folders, each once.
    package static func path(login: [String]? = nil) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let app = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let all = (login ?? []) + app + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/bin"]
        return all.reduce(into: [String]()) { if !$1.isEmpty, !$0.contains($1) { $0.append($1) } }
    }

    /// Each program the command runs by bare name, once, in the order it names them.
    static func programs(of words: [ShellWord], in folders: [String]) -> [Program] {
        let names = words.filter { $0.isCommand && !$0.expands && !$0.text.isEmpty && !$0.text.contains("/") }
            .map(\.text)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return names.map { Program(name: $0, found: executables(named: $0, in: folders)) }
    }

    /// Every executable called `name` in `folders`, in order. A folder linked into another
    /// counts once.
    static func executables(named name: String, in folders: [String]) -> [URL] {
        folders.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .filter { FileManager.default.isExecutableFile(atPath: $0.path) && !isFolder($0) }
            .reduce(into: [URL]()) { kept, url in
                let real = url.resolvingSymlinksInPath().path
                if !kept.contains(where: { $0.resolvingSymlinksInPath().path == real }) { kept.append(url) }
            }
    }

    /// A script outside the system's folders: text anyone could have written, so it is drawn.
    /// Wherever it sits in the `PATH` order — whether it runs depends on a `PATH` this cannot be
    /// sure of.
    static func isUserScript(_ url: URL) -> Bool {
        !isSystem(url) && startsWithShebang(url.resolvingSymlinksInPath())
    }

    package static func isSystem(_ url: URL) -> Bool {
        let real = url.resolvingSymlinksInPath().path
        return systemFolders.contains { real.hasPrefix($0) }
    }
}
