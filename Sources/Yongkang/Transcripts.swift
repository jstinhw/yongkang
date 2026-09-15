import Foundation

/// Where supported providers keep a session's own transcript. Naming it once keeps the
/// window and the usage screen looking in the same place.
enum Transcripts {
    static func url(of session: CodeSession, in directory: URL) -> URL? {
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

    static func usageURL(of session: CodeSession, in directory: URL) -> URL? {
        guard session.agent == .grok else { return url(of: session, in: directory) }
        return GrokTranscripts.usageURL(sessionID: session.id, projectDirectory: directory)
    }
}
