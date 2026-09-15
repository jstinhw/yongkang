import Foundation
import SwiftUI

/// Tokens spent, in the four buckets the supported providers report. Cache reads are kept apart
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

    /// Clamped at zero per bucket: a provider that resets its running total must read as
    /// no spend, never as negative spend that would cancel out real work beside it.
    static func - (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        TokenTally(input: max(0, lhs.input - rhs.input), output: max(0, lhs.output - rhs.output),
                   cacheRead: max(0, lhs.cacheRead - rhs.cacheRead),
                   cacheWrite: max(0, lhs.cacheWrite - rhs.cacheWrite))
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
    /// Every turn this agent took, kept as its own timestamped slice rather than summed on
    /// the way in — a total cannot be narrowed to the last hour afterwards, and the screen
    /// asks for exactly that.
    let samples: [UsageSample]

    /// `since` nil is all time; otherwise only what was spent after it.
    func samples(since: Date?) -> [UsageSample] {
        guard let since else { return samples }
        return samples.filter { $0.at >= since }
    }

    func models(since: Date?) -> [String: TokenTally] {
        samples(since: since).reduce(into: [:]) { $0[$1.model, default: TokenTally()] = $0[$1.model, default: TokenTally()] + $1.tally }
    }

    func tally(since: Date?) -> TokenTally {
        samples(since: since).map(\.tally).reduce(TokenTally(), +)
    }

    /// The one model to show on a one-line row: whichever spent the most in the window.
    func topModel(since: Date?) -> String? {
        models(since: since).max { $0.value.total < $1.value.total }?.key
    }

    var lastActive: Date? { samples.last?.at }
}

/// One turn's spend and when it happened. Each supported CLI stamps every record it writes, which
/// is what makes a window and a histogram possible at all.
struct UsageSample {
    let at: Date
    let model: String
    let tally: TokenTally
}

/// The window the usage screen is showing. Wider windows get wider buckets, so the
/// histogram is always about the same number of bars however far back it reaches.
enum UsageRange: String, CaseIterable, Identifiable {
    case hour = "1h"
    case day = "24h"
    case week = "7d"
    case all = "All"

    var id: Self { self }

    /// Nil for all time — there is no start to filter against.
    func since(now: Date = Date()) -> Date? {
        switch self {
        case .hour: return now.addingTimeInterval(-3_600)
        case .day: return now.addingTimeInterval(-86_400)
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .all: return nil
        }
    }

    var caption: String {
        switch self {
        case .hour: return "last hour"
        case .day: return "last 24 hours"
        case .week: return "last 7 days"
        case .all: return "all time"
        }
    }

    var buckets: Int {
        switch self {
        case .hour: return 12
        case .day: return 24
        case .week: return 14
        case .all: return 32
        }
    }
}

/// One column of the histogram: what was spent in that slice of time, split by model so a
/// bar says which model the work went to and not only how much of it there was.
struct UsageBucket: Identifiable {
    let id: Int
    let start: Date
    let byModel: [String: Int]

    var total: Int { byModel.values.reduce(0, +) }
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

    /// What a lead's runs are filed under. Named, because it is also what the usage screen
    /// matches on to call those runs by the lead's name rather than a numbered title.
    static let leadRole = "lead"

    // MARK: - Per-agent spend

    /// A session's role, for the panel that groups spend by one. The console names a
    /// session after what it started it for — "Engineering Lead", "Product", "Unblock
    /// <block>" — and numbers the second of each, so the first word is the role and the
    /// number is not. A subagent needs none of this: it already carries its agent type.
    static func role(of session: CodeSession) -> String {
        guard !session.isEngineeringLead else { return leadRole }
        return session.title.split(separator: " ").first.map { $0.lowercased() } ?? "session"
    }

    /// Every agent in the project with something on disk to read, biggest spender first.
    static func spends(in project: Project) -> [AgentSpend] {
        project.sessions.flatMap { session -> [AgentSpend] in
            let provider = session.agent ?? .claude
            let own = Transcripts.url(of: session, in: project.directory).map { url in
                AgentSpend(id: session.id.uuidString, tag: Tag.session(session),
                           name: session.title, role: role(of: session),
                           provider: provider, running: !session.exited,
                           samples: samples(at: Transcripts.usageURL(of: session, in: project.directory) ?? url,
                                            provider))
            }
            let spawned = session.subagents.map { subagent in
                // Scoped to its session: a provider's agent id is unique within the session
                // that spawned it and not beyond, so two sessions can hold the same one —
                // which would collide as a list key here and as a ledger row on disk.
                AgentSpend(id: "\(session.id.uuidString):\(subagent.id)",
                           tag: Tag.subagent(session, subagent),
                           name: subagent.description, role: subagent.agentType,
                           provider: provider, running: subagent.running,
                           samples: samples(at: subagent.transcriptURL, provider))
            }
            return ([own].compactMap { $0 } + spawned).filter { !$0.samples.isEmpty }
        }
    }

    /// Sums a keyed slice of the spends — by role, by provider — as one call, because
    /// those panels are the same fold over a different key.
    static func group<Key: Hashable>(_ spends: [AgentSpend], since: Date?,
                                     by key: (AgentSpend) -> Key) -> [(key: Key, tally: TokenTally)] {
        Dictionary(grouping: spends, by: key)
            .map { (key: $0.key, tally: $0.value.map { $0.tally(since: since) }.reduce(TokenTally(), +)) }
            .filter { $0.tally.total > 0 }
            .sorted { $0.tally.total > $1.tally.total }
    }

    static func byModel(_ spends: [AgentSpend], since: Date?) -> [(key: String, tally: TokenTally)] {
        spends.flatMap { $0.samples(since: since) }
            .reduce(into: [String: TokenTally]()) { $0[$1.model, default: TokenTally()] = $0[$1.model, default: TokenTally()] + $1.tally }
            .map { (key: $0.key, tally: $0.value) }
            .filter { $0.tally.total > 0 }
            .sorted { $0.tally.total > $1.tally.total }
    }

    /// The histogram: the range sliced into equal buckets, each holding what every model
    /// spent inside it. Samples outside the range fall outside the bucket index and are
    /// dropped here rather than filtered first.
    static func histogram(_ samples: [UsageSample], range: UsageRange,
                          now: Date = Date()) -> [UsageBucket] {
        let start: Date
        switch range {
        case .all:
            // An all-time view of a single afternoon should not draw a month of empty
            // bars, so it starts at the first sample — with an hour's floor, because a
            // range narrower than that divides into slivers.
            guard let first = samples.map(\.at).min() else { return [] }
            start = min(first, now.addingTimeInterval(-3_600))
        default:
            start = range.since(now: now) ?? now
        }
        let width = now.timeIntervalSince(start) / Double(range.buckets)
        guard width > 0 else { return [] }
        var columns = Array(repeating: [String: Int](), count: range.buckets)
        for sample in samples {
            // Clamped at the top rather than dropped: a turn written in the same instant
            // the screen loaded, or by a clock a little ahead, belongs in the last bucket
            // and not nowhere.
            let index = min(range.buckets - 1, Int(sample.at.timeIntervalSince(start) / width))
            guard index >= 0 else { continue }
            columns[index][sample.model, default: 0] += sample.tally.total
        }
        return columns.enumerated().map {
            UsageBucket(id: $0.offset, start: start.addingTimeInterval(width * Double($0.offset)),
                        byModel: $0.element)
        }
    }

    // MARK: - Reading a transcript

    /// What has already been read out of one file. A transcript only ever grows at the
    /// end, so a re-read parses the new lines and nothing else — which is what makes it
    /// safe to refresh this screen while a dozen agents are writing.
    private struct Cursor {
        var offset: UInt64 = 0
        var samples: [UsageSample] = []
        /// Codex only. It reports a running total per turn rather than a delta, so the
        /// previous total is kept to subtract — and the model comes off whichever
        /// `turn_context` came last, which may be in an earlier pass than the turn is.
        var running = TokenTally()
        var model = "unknown"
    }

    private static var files: [String: Cursor] = [:]

    static func samples(at url: URL, _ provider: AgentKind) -> [UsageSample] {
        var cursor = files[url.path] ?? Cursor()
        let lines = newLines(in: url, cursor: &cursor)
        for line in lines {
            let samples: [UsageSample]
            switch provider {
            case .codex: samples = codexSample(line, cursor: &cursor).map { [$0] } ?? []
            case .claude: samples = claudeSample(line).map { [$0] } ?? []
            case .grok: samples = grokSamples(line)
            case .agy: samples = []
            }
            cursor.samples += samples
        }
        files[url.path] = cursor
        return cursor.samples
    }

    /// Claude Code stamps every assistant message with its model and what that message
    /// cost, so the file is already a ledger of deltas — one line, one sample.
    private static func claudeSample(_ line: String) -> UsageSample? {
        guard line.contains("\"usage\""), let object = json(line),
              let at = date(object["timestamp"] as? String),
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let tally = TokenTally(input: count("input_tokens"), output: count("output_tokens"),
                               cacheRead: count("cache_read_input_tokens"),
                               cacheWrite: count("cache_creation_input_tokens"))
        return tally.total == 0 ? nil
            : UsageSample(at: at, model: message["model"] as? String ?? "unknown", tally: tally)
    }

    /// Codex reports the session's running total on every turn instead of that turn's
    /// cost, so each sample is the difference from the last one. Differencing telescopes:
    /// the samples always add back up to the total the file last reported, which summing
    /// its `last_token_usage` fields does not — those repeat within a turn.
    private static func codexSample(_ line: String, cursor: inout Cursor) -> UsageSample? {
        guard let object = json(line), let payload = object["payload"] as? [String: Any] else { return nil }
        // A turn names its model before it reports what the turn cost, and a session can
        // change model partway, so the latest one seen is the one a sample is filed under.
        if object["type"] as? String == "turn_context" {
            cursor.model = payload["model"] as? String ?? cursor.model
            return nil
        }
        guard payload["type"] as? String == "token_count",
              let at = date(object["timestamp"] as? String),
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any] else { return nil }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        // `input_tokens` is the whole prompt, cached part included, so the cached half is
        // subtracted out rather than counted twice.
        let cached = count("cached_input_tokens")
        let total = TokenTally(input: max(0, count("input_tokens") - cached),
                               output: count("output_tokens"), cacheRead: cached,
                               cacheWrite: count("cache_write_input_tokens"))
        let delta = total - cursor.running
        cursor.running = total
        return delta.total <= 0 ? nil : UsageSample(at: at, model: cursor.model, tally: delta)
    }

    /// Grok writes one completed-turn update with a per-model usage breakdown. Its input
    /// total includes cache reads, so subtract that part before putting it in our additive
    /// tally, the same way Codex's running total is handled above.
    private static func grokSamples(_ line: String) -> [UsageSample] {
        guard let object = json(line),
              let timestamp = (object["timestamp"] as? NSNumber)?.doubleValue,
              let params = object["params"] as? [String: Any],
              let update = params["update"] as? [String: Any],
              update["sessionUpdate"] as? String == "turn_completed",
              let usage = update["usage"] as? [String: Any]
        else { return [] }
        let at = Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)

        func sample(_ model: String, _ value: [String: Any]) -> UsageSample? {
            func count(_ key: String) -> Int { (value[key] as? NSNumber)?.intValue ?? 0 }
            let cached = count("cachedReadTokens")
            let tally = TokenTally(input: max(0, count("inputTokens") - cached),
                                   output: count("outputTokens"), cacheRead: cached,
                                   cacheWrite: count("cacheCreationTokens"))
            return tally.total == 0 ? nil : UsageSample(at: at, model: model, tally: tally)
        }

        let models = usage["modelUsage"] as? [String: Any] ?? [:]
        let split = models.compactMap { model, value in sample(model, value as? [String: Any] ?? [:]) }
        return split.isEmpty ? sample("grok", usage).map { [$0] } ?? [] : split
    }

    /// Whole lines written since this file was last read, advancing the cursor only past
    /// the newline — a half-written last line is left for the next pass rather than parsed.
    private static func newLines(in url: URL, cursor: inout Cursor) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
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

    static func date(_ text: String?) -> Date? {
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
        switch family(model) {
        case "opus": return Theme.violet
        case "sonnet": return Theme.accent
        case "haiku": return Theme.green
        case "fable": return Theme.amber
        default: return Theme.tx3
        }
    }

    private static func family(_ model: String) -> String {
        let name = model.lowercased()
        return ["opus", "sonnet", "haiku", "fable", "gpt", "codex"].first { name.contains($0) } ?? "other"
    }

    /// A colour per model for one render, rather than per family. Two versions of the same
    /// model are the same hue at different weights: a bar stacked out of one flat violet
    /// says how much went to Opus but not which Opus, which is half the question. Pass the
    /// models biggest-spender first, so the one that did most of the work is full strength.
    static func palette(for models: [String]) -> [String: Color] {
        var depth: [String: Int] = [:]
        return models.reduce(into: [:]) { palette, model in
            let step = depth[family(model), default: 0]
            depth[family(model)] = step + 1
            palette[model] = step == 0 ? modelTint(model)
                : modelTint(model).opacity(1 - 0.32 * Double(min(step, 2)))
        }
    }

    /// `claude-haiku-4-5-20251001` → `haiku-4-5`: the date stamp is noise in a legend.
    static func modelName(_ model: String) -> String {
        let stripped = model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
        let parts = stripped.split(separator: "-")
        guard let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) else { return stripped }
        return parts.dropLast().joined(separator: "-")
    }
}

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
