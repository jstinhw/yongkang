import Foundation

/// What every provider's reader needs from the files an agent CLI writes.
enum Transcripts {
    /// A file a CLI is still writing, as its lines that decode, joined back with newlines.
    /// Decoded a line at a time, not as one string: the CLI can be caught partway through a
    /// multi-byte character, and strict decoding of the whole file would lose every line
    /// for that one. A line that isn't valid UTF-8, which is that cut tail, is dropped.
    static func text(at url: URL) -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Not that the file isn't there — a session whose CLI has not written its transcript
            // yet is the normal case on every read. Anything else is a transcript pane that
            // draws empty for a live agent, which is the report this exists to answer.
            guard !Log.isMissing(error) else { return nil }
            Log.providers.error(
                "unreadable transcript \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        return data.split(separator: UInt8(ascii: "\n"))
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
