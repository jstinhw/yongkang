import Foundation

enum BundledSkills {
    /// The packaged `skills/` folder, or nil in a development build that has no Resources
    /// folder next to the binary.
    static var root: URL? {
        let executableResources = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        return [Bundle.main.resourceURL, executableResources].compactMap { $0 }
            .map { $0.appendingPathComponent("skills") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The packaged copy of one skill.
    static func url(_ name: String) -> URL? {
        guard let file = root?.appendingPathComponent("\(name)/SKILL.md"),
            FileManager.default.fileExists(atPath: file.path)
        else { return nil }
        return file
    }

    static func load(_ name: String) -> String? {
        url(name).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
