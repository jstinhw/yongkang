import Foundation

/// What an agent says a reviewer needs to decide on one attempt at a task, read from the JSON
/// in its run record's `## Review`. The review page is drawn from it, so a review reads the
/// same whichever agent wrote it — the move `Plan` made for plans, for the same reason: when
/// each agent drew its own report page, each was only as readable as the agent that drew it.
///
/// Only the claims the agent alone can make are here: how sure it is, what it checked, where a
/// person should look, what it wants to ask. The files, their line counts and the Done when
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
    package let spots: [Spot]?
    package let questions: [Question]?
    package let concerns: [Concern]?
    package let outside: [Outside]?
    package let files: [FileNote]?
    /// What landing this unblocks.
    package let next: String?

    /// A review whose own report argues against approving it as it stands: a check that
    /// failed, a low confidence, or a concern it says blocks.
    package var cautions: Bool {
        confidence == .low || (checks ?? []).contains { $0.status == .failed }
            || (concerns ?? []).contains { $0.blocks == true }
    }

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
