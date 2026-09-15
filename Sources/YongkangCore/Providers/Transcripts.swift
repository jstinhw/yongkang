import Foundation

/// Where supported providers keep a session's own transcript. Naming it once keeps the
/// window and the usage screen looking in the same place.
package enum Transcripts {
    package static func url(of session: CodeSession, in directory: URL) -> URL? {
        switch session.agent {
        case .codex:
            return CodexTranscripts.transcriptURL(sessionID: session.id, projectDirectory: directory)
        case .claude:
            return ClaudeTranscripts.transcriptURL(sessionID: session.id, projectDirectory: directory)
        case .grok:
            return GrokTranscripts.transcriptURL(sessionID: session.id, projectDirectory: directory)
        case .agy:
            return nil
        case nil:
            // A service terminal is a PTY in a folder, not an agent — it has no transcript.
            return nil
        }
    }

    package static func usageURL(of session: CodeSession, in directory: URL) -> URL? {
        guard session.agent == .grok else { return url(of: session, in: directory) }
        return GrokTranscripts.usageURL(sessionID: session.id, projectDirectory: directory)
    }

    /// A file a CLI is still writing, as its lines that decode, joined back with newlines.
    /// Decoded a line at a time, not as one string: the CLI can be caught partway through a
    /// multi-byte character, and strict decoding of the whole file would lose every line
    /// for that one. A line that isn't valid UTF-8, which is that cut tail, is dropped.
    static func text(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.split(separator: UInt8(ascii: "\n"))
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
