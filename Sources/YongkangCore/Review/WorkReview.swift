import Foundation

/// What an agent says a reviewer needs to decide on one attempt at a task, read from the JSON
/// in its run record's `## Review`. The review page is drawn from it, so a review reads the
/// same whichever agent wrote it — the move `Plan` made for plans, for the same reason: when
/// each agent drew its own report page, each was only as readable as the agent that drew it.
///
/// Only the claims the agent alone can make are here: how sure it is, what it checked, what the
/// change looks like, where a person might read, what it wants to ask. The files, their line counts and the Done when
/// are read from git and the task file, so the agent cannot misreport those. Read leniently,
/// like everything an agent writes: a summary and a confidence are required, every list may be
/// left out.
package struct WorkReview: Decodable, Equatable, Sendable {
    package enum Confidence: String, Decodable, Sendable { case high, medium, low }

    /// One thing the agent ran to check its work, and what it proved.
    package struct Check: Decodable, Equatable, Sendable {
        package enum Status: String, Decodable, Sendable {
            case passed, failed
            /// Could not be run here — a step that needs a tag, a device, a secret. Listed
            /// rather than left out, because what nobody checked is what the reviewer reads.
            case notRun = "not_run"
        }

        package let claim: String
        package let status: Status
        /// What it printed, in a few words.
        package let result: String?
        /// The command and its output, shown when the check is unfolded.
        package let command: String?
    }

    /// The change made visible, its before beside its after, so the reviewer looks at it rather
    /// than reads the code for it: the app itself running as it was and as it is, a case that
    /// went wrong and now does not, or the old and new text of a schema or an API.
    package struct Show: Decodable, Equatable, Sendable {
        /// `ui`, whose sides are the app running at two addresses, or two pictures of a native
        /// app's screen; `error`, a case run on both sides; anything else, `schema` and `api`
        /// among them, has text for sides. A string, so a kind the page does not know still
        /// shows, as text under its own name.
        package let kind: String
        package let title: String
        /// For `ui` the address the app as it was runs at, or its picture's path, otherwise what
        /// it was. Nil when there was nothing: a new screen, a new table.
        package let before: String?
        /// Nil when it is gone.
        package let after: String?
        /// `ui` only: the commands, run in the project, that serve each side again once the
        /// agent's own servers are gone. Never run without the user's say-so.
        package let serveBefore: String?
        package let serveAfter: String?
        /// `ui` only: CSS selectors of what changed, outlined on whichever side has them, so
        /// what went away is marked on the before and what is new on the after.
        package let highlight: [String]?
        /// The test that runs an `error` case, for the reviewer to run again.
        package let test: String?
        /// What the agent wants said beside it: a difference it kept on purpose.
        package let note: String?

        /// A side of a `ui` show as a page to load: a web address on this Mac and nothing else,
        /// so a path or a script in the agent's JSON is never handed to a web view, and opening a
        /// review never sends a request to a server the agent named, past its sandbox.
        package static func page(_ address: String?) -> URL? {
            guard let address, let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased()),
                DemoServer.isLocal(url)
            else { return nil }
            return url
        }

        /// A side of a `ui` show as a picture: a screen no browser draws, a native app's, drawn
        /// offscreen by the agent. An image file on this Mac that is there, by its absolute path,
        /// and only ever decoded as an image, so a path in the agent's JSON never shows a file
        /// that is not a picture.
        package static func picture(_ path: String?) -> URL? {
            guard let path, path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: path)
            guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
                FileManager.default.fileExists(atPath: url.path)
            else { return nil }
            return url
        }

        /// Whether the page can draw it. A screen with no side it can load — a page that is not
        /// on this Mac, a picture that is gone — would be a tall box saying so: it is left out,
        /// and what changed on screen is in `changed`.
        package var drawable: Bool {
            kind != "ui" || [before, after].contains { Self.page($0) != nil || Self.picture($0) != nil }
        }
    }

    /// A place the agent wants a person to read: what no check covers.
    package struct Spot: Decodable, Equatable, Sendable {
        package let path: String
        /// The first and last line, in the file as it is now.
        package let lines: [Int]?
        /// Where in the file, in a word or two: a function, a step, a key.
        package let label: String?
        package let why: String

        /// The lines it names, when they make a range.
        package var range: ClosedRange<Int>? {
            guard let first = lines?.first, let last = lines?.last, first > 0, first <= last else { return nil }
            return first...last
        }

        /// The part of the file's diff this spot is about: its changed and kept lines, with
        /// the removed lines among and right around them, which have no new number of their own.
        package func excerpt(of diff: [DiffLine]) -> [DiffLine] {
            guard let range else { return [] }
            let inside = diff.indices.filter { Int(diff[$0].new).map(range.contains) ?? false }
            guard var start = inside.first, var end = inside.last else { return [] }
            while start > diff.startIndex, diff[start - 1].kind == .remove { start -= 1 }
            while end + 1 < diff.endIndex, diff[end + 1].kind == .remove { end += 1 }
            return Array(diff[start...end])
        }
    }

    /// Something only the user can decide, with the agent's pick.
    package struct Question: Decodable, Equatable, Sendable {
        package let ask: String
        package let context: String?
        package let options: [String]?
        /// The index of the option the agent would pick.
        package let recommend: Int?
    }

    package struct Concern: Decodable, Equatable, Sendable {
        package let title: String
        package let detail: String?
        /// True when the work should not be approved until it is settled.
        package let blocks: Bool?
    }

    /// Something the agent did outside this repo: a network read, a download, a write.
    package struct Outside: Decodable, Equatable, Sendable {
        /// `read`, `local` or `write`.
        package let kind: String
        package let what: String
    }

    /// Why one of the task's files changed.
    package struct FileNote: Decodable, Equatable, Sendable {
        package let path: String
        package let why: String
    }

    /// What changed, in one sentence.
    package let summary: String
    package let confidence: Confidence
    package let confidenceWhy: String?
    /// What the work touches, in a few words: "CI and update feed".
    package let touches: String?
    /// Outcomes someone can see or check, not files.
    package let changed: [String]?
    package let checks: [Check]?
    /// What keeps the work safe whatever the code does: nothing ships until a tag is pushed.
    package let holds: [String]?
    package let shows: [Show]?
    package let spots: [Spot]?
    package let questions: [Question]?
    package let concerns: [Concern]?
    package let outside: [Outside]?
    package let files: [FileNote]?
    /// What landing this unblocks.
    package let next: String?

    /// What in its own report argues against approving it as it stands, in a few words: a check
    /// that failed, then a concern it says blocks, then a low confidence. Nil when nothing does.
    package var caution: String? {
        if let check = checks?.first(where: { $0.status == .failed }) { return "Check failed: \(check.claim)" }
        if let concern = concerns?.first(where: { $0.blocks == true }) { return concern.title }
        return confidence == .low ? "Low confidence" : nil
    }

    package var cautions: Bool { caution != nil }

    /// The review in a run record's `## Review` section: nil when there is none, and otherwise
    /// the review or which field kept it from being read — what the agent needs to be told.
    /// The JSON is taken from its first `{` to its last `}`, so a fence around it, or a line
    /// before it, does not matter.
    package static func read(_ section: String) -> Result<WorkReview, Problem>? {
        guard let start = section.firstIndex(of: "{"), let end = section.lastIndex(of: "}"), start < end else {
            return section.isEmpty ? nil : .failure(Problem(reason: "There is no JSON object in it."))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return .success(try decoder.decode(WorkReview.self, from: Data(section[start...end].utf8)))
        } catch {
            return .failure(Problem(reason: decodingProblem(error)))
        }
    }

    package struct Problem: Error, Equatable, Sendable {
        package let reason: String
    }
}

/// Which field of an agent's JSON was wrong, which is what the agent needs to be told to fix it.
package func decodingProblem(_ error: any Error) -> String {
    let path = { (keys: [any CodingKey]) in
        keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context): return "\(path(context.codingPath + [key])) is missing."
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
        return "\(path(context.codingPath)): \(context.debugDescription)"
    case DecodingError.dataCorrupted(let context): return context.debugDescription
    default: return error.localizedDescription
    }
}
