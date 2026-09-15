import Foundation

package enum AgentKind: String, CaseIterable, Identifiable {
    case claude
    case codex
    case grok
    case agy

    package var id: Self { self }
    package var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok"
        case .agy: "Agy"
        }
    }
    package var systemImage: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .grok: "bolt"
        case .agy: "a.circle"
        }
    }
    var command: String { rawValue }

    func skillInvocation(_ name: String, arguments: String) -> String {
        "\(self == .codex ? "$" : "/")\(name) \(arguments)"
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
