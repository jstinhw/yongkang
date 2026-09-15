import Foundation

/// Reads the session Grok writes for the UUID Yongkang passes with `--session-id`.
package enum GrokTranscripts {
    static func projectFolder(
        projectDirectory: URL,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> URL {
        let allowed = CharacterSet(
            charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let sessions = grokHome.appendingPathComponent("sessions", isDirectory: true)
        let encoded =
            projectDirectory.path.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? projectDirectory.path.replacingOccurrences(of: "/", with: "%2F")
        let direct = sessions.appendingPathComponent(encoded, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: direct.path) else { return direct }

        // Grok shortens encoded paths beyond one filename's limit and leaves the original
        // cwd in the group, so only that uncommon case needs a directory scan.
        return
            ((try? FileManager.default.contentsOfDirectory(
                at: sessions, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .first {
                let cwd = try? String(contentsOf: $0.appendingPathComponent(".cwd"), encoding: .utf8)
                return cwd?.trimmingCharacters(in: .whitespacesAndNewlines) == projectDirectory.path
            } ?? direct
    }

    static func sessionFolder(
        sessionID: UUID, projectDirectory: URL,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> URL {
        projectFolder(projectDirectory: projectDirectory, grokHome: grokHome)
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    }

    static func transcriptURL(
        sessionID: UUID, projectDirectory: URL,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> URL {
        sessionFolder(sessionID: sessionID, projectDirectory: projectDirectory, grokHome: grokHome)
            .appendingPathComponent("chat_history.jsonl")
    }

    static func usageURL(
        sessionID: UUID, projectDirectory: URL,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> URL {
        sessionFolder(sessionID: sessionID, projectDirectory: projectDirectory, grokHome: grokHome)
            .appendingPathComponent("updates.jsonl")
    }

    package static func transcript(at url: URL) -> [TranscriptLine] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").flatMap { line -> [TranscriptLine] in
            guard let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [] }

            switch object["type"] as? String {
            case "user":
                let text = ClaudeTranscripts.resultText(object["content"])
                return text.isEmpty ? [] : [TranscriptLine(label: "Task", text: ClaudeTranscripts.truncate(text))]
            case "assistant":
                var lines: [TranscriptLine] = []
                let reply = ClaudeTranscripts.resultText(object["content"])
                if !reply.isEmpty { lines.append(TranscriptLine(label: "Reply", text: reply)) }
                lines += (object["tool_calls"] as? [[String: Any]] ?? []).map { call in
                    let name = call["name"] as? String ?? "tool"
                    let input = arguments(call["arguments"])
                    return TranscriptLine(label: "Tool", text: input.isEmpty ? name : "\(name)(\(input))")
                }
                return lines
            case "tool_result":
                let text = ClaudeTranscripts.resultText(object["content"])
                return text.isEmpty ? [] : [TranscriptLine(label: "Result", text: ClaudeTranscripts.truncate(text))]
            default:
                return []
            }
        }
    }

    private static func arguments(_ value: Any?) -> String {
        guard let text = value as? String else {
            return ClaudeTranscripts.truncate(ClaudeTranscripts.describe(value))
        }
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return ClaudeTranscripts.truncate(text)
        }
        return ClaudeTranscripts.truncate(ClaudeTranscripts.describe(object))
    }
}
