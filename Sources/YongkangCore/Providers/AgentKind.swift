import Foundation

package enum AgentKind: String, CaseIterable, Identifiable {
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
