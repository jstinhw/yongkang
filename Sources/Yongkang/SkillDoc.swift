import Foundation

/// A skill as it reads on screen: what the file calls itself, the one line it summarises
/// itself with, the tools it is allowed, and the instructions themselves — the same text
/// that gets pasted into an agent's opening prompt.
struct SkillDoc: Identifiable, Equatable {
    let name: String
    let summary: String
    let tools: [String]
    let body: String
    let url: URL?

    var id: String { name }

    /// The skill this name resolves to for a project — the same file the provider running
    /// the agent would load, wherever it is installed.
    static func load(_ name: String, project: URL?) -> SkillDoc {
        guard let url = Skills.url(name, project: project) else {
            return SkillDoc(name: name, summary: "", tools: [], body: "", url: nil)
        }
        return load(at: url, named: name)
    }

    static func load(at url: URL, named name: String) -> SkillDoc {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return SkillDoc(name: name, summary: "", tools: [], body: "", url: nil)
        }
        return parse(text, named: name, at: url)
    }

    /// The same skill under the name it is installed as. Frontmatter is what a skill says
    /// about itself; the folder is what an agent can actually ask for.
    func named(_ name: String) -> SkillDoc {
        SkillDoc(name: name, summary: summary, tools: tools, body: body, url: url)
    }

    static func parse(_ text: String, named name: String, at url: URL? = nil) -> SkillDoc {
        let fields = NotebookIndex.frontmatter(text)
        return SkillDoc(
            name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? name,
            summary: fields["description"] ?? "",
            tools: tools(text, inline: fields["allowed-tools"]),
            body: NotebookIndex.body(text),
            url: url)
    }

    /// `allowed-tools` is the one field a skill writes as a YAML block list, which the flat
    /// frontmatter reader returns empty. Scanning is bounded to the frontmatter block so a
    /// Markdown bullet in the body can never be mistaken for another tool.
    private static func tools(_ text: String, inline: String?) -> [String] {
        if let inline, !inline.isEmpty { return NotebookIndex.list(inline) }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }
        let front = Array(lines.dropFirst().prefix { $0.trimmingCharacters(in: .whitespaces) != "---" })
        guard let start = front.firstIndex(where: { $0.hasPrefix("allowed-tools:") }) else { return [] }
        return front[(start + 1)...]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .prefix { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
    }
}
