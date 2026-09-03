import Foundation
import SwiftUI

/// Tokens spent, in the four buckets both providers report. Cache reads are kept apart
/// from fresh input on purpose: they are the bulk of an agent's traffic and priced
/// nothing like it, so folding them together makes every agent look identical.
struct TokenTally: Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var total: Int { input + output + cacheRead + cacheWrite }
    /// What the context was already holding — the number that says whether an agent is
    /// re-reading its own history or actually doing new work.
    var cacheRate: Double { total == 0 ? 0 : Double(cacheRead) / Double(total) }

    static func + (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        TokenTally(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
                   cacheRead: lhs.cacheRead + rhs.cacheRead, cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }
}

/// One agent — a session, or a subagent it spawned — and what it has spent, per model.
/// A session and its subagents are separate rows: the lead's own spend is its planning,
/// and the specialists' is the work, and the two are worth telling apart.
struct AgentSpend: Identifiable {
    let id: String
    /// The selection tag that opens this agent, so a row in the usage screen goes
    /// straight to the transcript it is describing.
    let tag: String
    let name: String
    let role: String
    let provider: AgentKind
    let running: Bool
    let models: [String: TokenTally]

    var tally: TokenTally { models.values.reduce(TokenTally(), +) }
    /// The one model to show on a one-line row: whichever spent the most.
    var topModel: String? { models.max { $0.value.total < $1.value.total }?.key }
}

/// One rate-limit window a provider reports — the 5-hour session and the weekly bar both
/// CLIs draw, plus whatever per-model windows the plan carries.
struct PlanWindow: Identifiable {
    let id: String
    let name: String
    /// 0–100, as both providers report it.
    let percent: Double
    let resetsAt: Date?
}

/// What one coding tool says about the plan behind it. Read from that tool's own cache on
/// disk — neither exposes an API for this, so an unread field just leaves the card empty
/// rather than breaking anything.
struct ProviderQuota {
    let provider: AgentKind
    var plan: String?
    var windows: [PlanWindow] = []
    /// What is on the meter beyond the plan, already worded by the provider that reported
    /// it — Claude meters what has been spent, Codex what is left, and one number labelled
    /// two ways would be a lie half the time.
    var credits: (label: String, value: String)?
    /// When the numbers were written. Both caches are refreshed by the CLI, not by this
    /// app, so a quiet tool shows a stale bar and has to say so.
    var asOf: Date?
}

enum AgentUsage {

    // MARK: - Per-agent spend

    /// A session's role, for the panel that groups spend by one. The console names a
    /// session after what it started it for — "Engineering Lead", "Product", "Unblock
    /// <block>" — and numbers the second of each, so the first word is the role and the
    /// number is not. A subagent needs none of this: it already carries its agent type.
    static func role(of session: CodeSession) -> String {
        guard !session.isEngineeringLead else { return "lead" }
        return session.title.split(separator: " ").first.map { $0.lowercased() } ?? "session"
    }

    /// Every agent in the project with something on disk to read, biggest spender first.
    static func spends(in project: Project) -> [AgentSpend] {
        project.sessions.flatMap { session -> [AgentSpend] in
            let provider = session.agent ?? .claude
            let own = Transcripts.url(of: session, in: project.directory).map { url in
                AgentSpend(id: session.id.uuidString, tag: Tag.transcript(session.id),
                           name: session.title, role: role(of: session),
                           provider: provider, running: !session.exited, models: models(at: url, provider))
            }
            let spawned = session.subagents.map { subagent in
                AgentSpend(id: subagent.id, tag: Tag.subagent(session, subagent),
                           name: subagent.description, role: subagent.agentType,
                           provider: provider, running: subagent.running,
                           models: models(at: subagent.transcriptURL, provider))
            }
            return ([own].compactMap { $0 } + spawned).filter { $0.tally.total > 0 }
        }
        .sorted { $0.tally.total > $1.tally.total }
    }

    /// Sums a keyed slice of the spends — by model, by role, by provider — as one call,
    /// because all three panels on the usage screen are the same fold over a different key.
    static func group<Key: Hashable>(_ spends: [AgentSpend],
                                     by key: (AgentSpend) -> Key) -> [(key: Key, tally: TokenTally)] {
        Dictionary(grouping: spends, by: key)
            .map { (key: $0.key, tally: $0.value.map(\.tally).reduce(TokenTally(), +)) }
            .sorted { $0.tally.total > $1.tally.total }
    }

    static func byModel(_ spends: [AgentSpend]) -> [(key: String, tally: TokenTally)] {
        spends.flatMap { spend in spend.models.map { (model: $0.key, tally: $0.value) } }
            .reduce(into: [String: TokenTally]()) { $0[$1.model, default: TokenTally()] = $0[$1.model, default: TokenTally()] + $1.tally }
            .map { (key: $0.key, tally: $0.value) }
            .sorted { $0.tally.total > $1.tally.total }
    }

    // MARK: - Reading a transcript

    /// Bytes already folded into `tallies`, per file. A transcript only ever grows at the
    /// end, so a re-read parses the new lines and nothing else — which is what makes it
    /// safe to refresh this screen while a dozen agents are writing.
    private static var cursors: [String: UInt64] = [:]
    private static var tallies: [String: [String: TokenTally]] = [:]

    static func models(at url: URL, _ provider: AgentKind) -> [String: TokenTally] {
        provider == .codex ? codexModels(at: url) : claudeModels(at: url)
    }

    /// Claude Code writes one `usage` block per assistant message, so the file is the
    /// ledger: every block is a delta and they add up.
    static func claudeModels(at url: URL) -> [String: TokenTally] {
        var totals = tallies[url.path] ?? [:]
        for line in newLines(in: url) {
            guard line.contains("\"usage\""), let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            let model = message["model"] as? String ?? "unknown"
            func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            totals[model, default: TokenTally()] = totals[model, default: TokenTally()] + TokenTally(
                input: count("input_tokens"), output: count("output_tokens"),
                cacheRead: count("cache_read_input_tokens"), cacheWrite: count("cache_creation_input_tokens"))
        }
        tallies[url.path] = totals
        return totals
    }

    /// Codex reports a running total instead of deltas, so the last `token_count` event is
    /// the whole answer and the file is read from the tail rather than accumulated. The
    /// model comes off `turn_context`, which is written once near the head.
    static func codexModels(at url: URL) -> [String: TokenTally] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 65_536
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        guard let usage = tail.split(separator: "\n").reversed()
            .compactMap({ line -> [String: Any]? in
                guard line.contains("\"token_count\""), let object = json(String(line)),
                      let info = (object["payload"] as? [String: Any])?["info"] as? [String: Any]
                else { return nil }
                return info["total_token_usage"] as? [String: Any]
            }).first else { return [:] }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        // `input_tokens` is the whole prompt, cached part included, so the cached half is
        // subtracted out rather than counted twice.
        let cached = count("cached_input_tokens")
        return [codexModel(at: url): TokenTally(input: max(0, count("input_tokens") - cached),
                                                output: count("output_tokens"),
                                                cacheRead: cached,
                                                cacheWrite: count("cache_write_input_tokens"))]
    }

    private static var codexModelCache: [String: String] = [:]

    private static func codexModel(at url: URL) -> String {
        if let known = codexModelCache[url.path] { return known }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "unknown" }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 512_000)) ?? Data(), as: UTF8.self)
        let model = head.split(separator: "\n").lazy
            .filter { $0.contains("\"turn_context\"") }
            .compactMap { (json(String($0))?["payload"] as? [String: Any])?["model"] as? String }
            .first ?? "unknown"
        codexModelCache[url.path] = model
        return model
    }

    /// Whole lines written since this file was last read, advancing the cursor only past
    /// the newline — a half-written last line is left for the next pass rather than parsed.
    private static func newLines(in url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = cursors[url.path] ?? 0
        // A file that shrank was replaced, not appended to; start it over.
        guard size != start else { return [] }
        try? handle.seek(toOffset: size > start ? start : 0)
        if size < start { tallies[url.path] = nil }
        let data = (try? handle.readToEnd()) ?? Data()
        guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        cursors[url.path] = (size > start ? start : 0) + UInt64(end) + 1
        return String(decoding: data[..<end], as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Plan limits

    /// Claude Code caches what the API told it about the plan in `~/.claude.json`, and
    /// refreshes it as it works. Nothing here is a published API, so a missing field
    /// leaves a bar out instead of failing.
    static func claudeQuota(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    ) -> ProviderQuota? {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cached = root["cachedUsageUtilization"] as? [String: Any],
              let utilization = cached["utilization"] as? [String: Any] else { return nil }

        var quota = ProviderQuota(provider: .claude,
                                  plan: (root["oauthAccount"] as? [String: Any])?["organizationType"] as? String)
        if let ms = (cached["fetchedAtMs"] as? NSNumber)?.doubleValue {
            quota.asOf = Date(timeIntervalSince1970: ms / 1000)
        }
        // The named windows, in the order the CLI itself shows them. Per-model bars only
        // exist on plans that meter per model, so they are read and skipped when null.
        let named: [(String, String)] = [
            ("five_hour", "Session · 5h"), ("seven_day", "Weekly · all models"),
            ("seven_day_opus", "Weekly · Opus"), ("seven_day_sonnet", "Weekly · Sonnet"),
        ]
        quota.windows = named.compactMap { key, name in
            guard let window = utilization[key] as? [String: Any],
                  let percent = (window["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return PlanWindow(id: key, name: name, percent: percent,
                              resetsAt: date(window["resets_at"] as? String))
        }
        if let spend = utilization["spend"] as? [String: Any],
           let used = money(spend["used"] as? [String: Any] ?? [:]),
           let limit = money(spend["limit"] as? [String: Any] ?? [:]) {
            quota.credits = ("Extra usage", String(format: "$%.2f of $%.2f", used, limit))
        }
        return quota
    }

    /// `{amount_minor: 1000, exponent: 2}` → 10.00.
    private static func money(_ value: [String: Any]) -> Double? {
        guard let minor = (value["amount_minor"] as? NSNumber)?.doubleValue else { return nil }
        return minor / pow(10, (value["exponent"] as? NSNumber)?.doubleValue ?? 2)
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Codex has no config cache for this: the limits ride along on every turn's
    /// `token_count` event, so the newest rollout that carries one is the current answer.
    static func codexQuota(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) -> ProviderQuota? {
        let root = codexHome.appendingPathComponent("sessions")
        guard let walk = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return nil }
        let newest = walk.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(8)
        for url in newest {
            guard let limits = codexRateLimits(at: url) else { continue }
            var quota = ProviderQuota(provider: .codex, plan: limits["plan_type"] as? String)
            quota.asOf = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            quota.windows = [("primary", "Session · 5h"), ("secondary", "Weekly")]
                .compactMap { key, name -> PlanWindow? in
                    guard let window = limits[key] as? [String: Any],
                          let percent = (window["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                    let resets = (window["resets_at"] as? NSNumber)?.doubleValue
                    return PlanWindow(id: key, name: name, percent: percent,
                                      resetsAt: resets.map { Date(timeIntervalSince1970: $0) })
                }
            // Only when the account actually has credits: a zero balance on an account
            // that never bought any is not a fact worth a row.
            if let credits = limits["credits"] as? [String: Any],
               credits["has_credits"] as? Bool == true {
                quota.credits = ("Credits left",
                                 credits["unlimited"] as? Bool == true ? "unlimited"
                                     : "$\(credits["balance"] as? String ?? "0")")
            }
            return quota
        }
        return nil
    }

    private static func codexRateLimits(at url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 65_536
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        return tail.split(separator: "\n").reversed().lazy
            .filter { $0.contains("\"rate_limits\"") }
            .compactMap { (json(String($0))?["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] }
            .first
    }

    // MARK: - Formatting

    /// Token counts run to the tens of millions, and the exact digit never matters — what
    /// matters is which agent is an order of magnitude past the others.
    static func short(_ count: Int) -> String {
        switch count {
        case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
        case 10_000...: return "\(count / 1000)K"
        case 1_000...: return String(format: "%.1fK", Double(count) / 1000)
        default: return "\(count)"
        }
    }

    /// How long ago something was written. A quota is only as fresh as the last turn that
    /// wrote it, so a tool that has been quiet all day has to say so rather than look current.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        span(now.timeIntervalSince(date)).map { "\($0) ago" } ?? "just now"
    }

    /// "2h 14m", "6d", or nil once the window has already rolled over.
    static func until(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        return span(date.timeIntervalSince(now))
    }

    private static func span(_ interval: TimeInterval) -> String? {
        let seconds = Int(interval)
        guard seconds > 0 else { return nil }
        if seconds >= 86_400 { return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h" }
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return "\(max(1, seconds / 60))m"
    }

    /// A bar's colour is its headroom, not its provider: the point of the number is how
    /// close the work is to stopping.
    static func tint(_ percent: Double) -> Color {
        switch percent {
        case 90...: return Theme.red
        case 70...: return Theme.amber
        default: return Theme.green
        }
    }

    /// One colour per model family, held steady across every panel so a slice in the model
    /// bar and a label on an agent row are recognisably the same thing.
    static func modelTint(_ model: String) -> Color {
        let name = model.lowercased()
        if name.contains("opus") { return Theme.violet }
        if name.contains("sonnet") { return Theme.accent }
        if name.contains("haiku") { return Theme.green }
        if name.contains("fable") { return Theme.amber }
        return Theme.tx3
    }

    /// `claude-haiku-4-5-20251001` → `haiku-4-5`: the date stamp is noise in a legend.
    static func modelName(_ model: String) -> String {
        let stripped = model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
        let parts = stripped.split(separator: "-")
        guard let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) else { return stripped }
        return parts.dropLast().joined(separator: "-")
    }
}

/// Where each provider keeps a session's own transcript. Both readers already know this;
/// naming it once is what keeps the window and the usage screen looking in the same place.
enum Transcripts {
    static func url(of session: CodeSession, in directory: URL) -> URL? {
        switch session.agent {
        case .codex:
            return CodexTranscripts.transcriptURL(sessionID: session.id, projectDirectory: directory)
        case .claude:
            return ClaudeTranscripts.transcriptURL(sessionID: session.id, projectDirectory: directory)
        case nil:
            // A service terminal is a PTY in a folder, not an agent — it has no transcript.
            return nil
        }
    }
}
