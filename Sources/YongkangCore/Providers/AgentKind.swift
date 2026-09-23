import Foundation

package enum AgentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case grok
    case agy

    package var id: Self { self }

    /// The CLI behind this kind. The raw value is what persists, in a session's row and the
    /// agent switch; everything else about the CLI is its provider's.
    package var provider: any AgentProvider {
        switch self {
        case .claude: ClaudeCodeProvider.shared
        case .codex: CodexProvider.shared
        case .grok: GrokProvider.shared
        case .agy: AgyProvider()
        }
    }

    package var displayName: String { provider.displayName }
    package var systemImage: String { provider.systemImage }
    /// The executable on PATH, which is why a case is named after it.
    var command: String { rawValue }

    func skillInvocation(_ name: String, arguments: String) -> String {
        "\(provider.skillPrefix)\(name) \(arguments)"
    }

    /// Packaged sessions carry the app's exact skill text, so opening another project
    /// cannot silently pick a stale global skill or no skill at all. `instructions` keeps
    /// the pure branch testable; development builds fall back to native discovery.
    func skill(_ name: String, arguments: String, instructions: String? = nil) -> String {
        guard let instructions = instructions ?? BundledSkills.load(name) else {
            return skillInvocation(name, arguments: arguments)
        }
        return """
            Follow the bundled `\(name)` skill below. Treat `<arguments>` as `$ARGUMENTS`.

            <skill>
            \(instructions)
            </skill>

            <arguments>
            \(arguments)
            </arguments>
            """
    }
}

extension AgentKind {
    /// Which CLIs the login shell finds on PATH: the shell a session starts in, so a CLI that is
    /// only on Terminal's PATH still counts. Nil when the shell could not be run, which is not
    /// the same answer as none found.
    ///
    /// One shell asks for all of them, because an interactive zsh can take a second to start
    /// and that second should be paid once. Each hit is printed behind a marker, so whatever the
    /// user's rc files print on the way in is not read as a CLI.
    package static func installed(shell: [String] = ["/bin/zsh", "-ilc"]) async -> Set<AgentKind>? {
        let marker = "yongkang-found:"
        let script = allCases.map { "command -v \($0.command) >/dev/null 2>&1 && echo \(marker)\($0.command)" }
            .joined(separator: "; ")
        guard
            let output = try? await AsyncProcess.run(
                URL(fileURLWithPath: shell[0]), Array(shell.dropFirst()) + [script])
        else { return nil }
        return Set(
            output.text.split(whereSeparator: \.isNewline).compactMap { line in
                line.hasPrefix(marker) ? AgentKind(rawValue: String(line.dropFirst(marker.count))) : nil
            })
    }
}
