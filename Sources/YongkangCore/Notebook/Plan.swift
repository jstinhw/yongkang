import Foundation

/// A plan as setup and Product hand it over: `.notebook/pages/<session>.json`
/// (`NotebookFormat.plan(of:in:)`), which the app lays out (`PlanDrawing`) and draws on the
/// session's Page tab. The agent says what is in the plan and nothing about how it looks.
///
/// Like `pages/` itself it is a channel to the app rather than notebook content, so the spec
/// does not list it; the prompt that asks for it carries its shape. Read leniently, like
/// everything an agent writes: only the title and each entry's id and title are required.
package struct Plan: Decodable, Equatable, Sendable {
    package struct Task: Decodable, Equatable, Sendable {
        package let id: String
        /// What it changes, in a few words: the one line on its card.
        package let title: String
        package let project: String?
        package let dependsOn: [String]?
        /// Design work, settled by a designer before the tasks that build it start.
        package let design: Bool?
        /// One line more, shown when the task is picked.
        package let detail: String?
    }

    /// Something the plan's tasks depend on that it does not build: what already exists, or a
    /// task another project's board delivers.
    package struct Outside: Decodable, Equatable, Sendable {
        package let id: String
        package let title: String
        /// Its project, or the other project's folder.
        package let place: String?
        /// False while it does not exist yet, which keeps what waits on it from starting.
        /// Left out, it exists: that is what the plan mostly builds on.
        package let done: Bool?

        private enum CodingKeys: String, CodingKey {
            case id, title, done
            case place = "where"
        }
    }

    /// One moment the plan waits on the user: what they do, and the task it belongs to.
    package struct Ask: Codable, Equatable, Sendable {
        package let task: String
        package let action: String
    }

    package let title: String
    /// What someone can do once every task lands.
    package let outcomes: [String]?
    package let needsYou: [Ask]?
    package let tasks: [Task]
    package let outside: [Outside]?

    /// The plan in `url`, or why it could not be read: a decoding error names the field.
    package static func load(_ url: URL) throws -> Plan {
        try decode(Data(contentsOf: url))
    }

    package static func decode(_ data: Data) throws -> Plan {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Plan.self, from: data)
    }
}
