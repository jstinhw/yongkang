import Foundation

/// One provider's place in every usage file it has read. A transcript only ever grows at the
/// end, so a re-read parses the new lines and nothing else — which is what makes it safe to
/// refresh the usage screen while a dozen agents are writing.
///
/// Each provider owns one, so no two share a cursor, and the actor keeps the poll and the
/// usage screen from moving the same cursor at once.
actor UsageReader {
    /// What has already been read out of one file.
    struct Cursor {
        var offset: UInt64 = 0
        var samples: [UsageSample] = []
        /// Codex only. It reports a running total per turn rather than a delta, so the
        /// previous total is kept to subtract — and the model comes off whichever
        /// `turn_context` came last, which may be in an earlier pass than the turn is.
        var running = TokenTally()
        var model = "unknown"
    }

    private var files: [String: Cursor] = [:]
    /// The samples in one whole line, given the cursor it is read with.
    private let parse: @Sendable (_ line: String, _ cursor: inout Cursor) -> [UsageSample]

    init(parse: @escaping @Sendable (_ line: String, _ cursor: inout Cursor) -> [UsageSample]) {
        self.parse = parse
    }

    /// Every sample in the file so far, parsing only what was written since the last read.
    func samples(at url: URL) -> [UsageSample] {
        var cursor = files[url.path] ?? Cursor()
        for line in Self.newLines(in: url, cursor: &cursor) {
            let samples = parse(line, &cursor)
            cursor.samples += samples
        }
        files[url.path] = cursor
        return cursor.samples
    }

    /// Whole lines written since this file was last read, advancing the cursor only past
    /// the newline — a half-written last line is left for the next pass rather than parsed.
    private static func newLines(in url: URL, cursor: inout Cursor) -> [String] {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            // A usage file the CLI has not written yet is normal and says nothing. Anything
            // else is a live agent whose spend silently stops counting.
            guard !Log.isMissing(error) else { return [] }
            Log.providers.error(
                "unreadable usage file \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size != cursor.offset else { return [] }
        // A file that shrank was replaced, not appended to; start it over.
        if size < cursor.offset { cursor = Cursor() }
        try? handle.seek(toOffset: cursor.offset)
        let data = (try? handle.readToEnd()) ?? Data()
        guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        cursor.offset += UInt64(end) + 1
        return String(decoding: data[..<end], as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
