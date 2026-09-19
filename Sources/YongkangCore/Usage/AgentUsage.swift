import Foundation

/// Tokens spent, in the four buckets the supported providers report. Cache reads are kept apart
/// from fresh input on purpose: they are the bulk of an agent's traffic and priced
/// nothing like it, so folding them together makes every agent look identical.
package struct TokenTally: Equatable, Sendable {
    package var input = 0
    package var output = 0
    package var cacheRead = 0
    package var cacheWrite = 0

    package init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    package var total: Int { input + output + cacheRead + cacheWrite }
    /// What the context was already holding — the number that says whether an agent is
    /// re-reading its own history or actually doing new work.
    package var cacheRate: Double { total == 0 ? 0 : Double(cacheRead) / Double(total) }

    package static func + (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        TokenTally(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead, cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }

    /// Clamped at zero per bucket: a provider that resets its running total must read as
    /// no spend, never as negative spend that would cancel out real work beside it.
    static func - (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        TokenTally(
            input: max(0, lhs.input - rhs.input), output: max(0, lhs.output - rhs.output),
            cacheRead: max(0, lhs.cacheRead - rhs.cacheRead),
            cacheWrite: max(0, lhs.cacheWrite - rhs.cacheWrite))
    }
}

/// One agent — a session, or a subagent it spawned — and what it has spent, per model.
/// A session and its subagents are separate rows: a session splitting a project spends on
/// planning, and its subagents on the work, and the two are worth telling apart.
package struct AgentSpend: Identifiable, Sendable {
    package let id: String
    /// The route that opens this agent, so a row in the usage screen goes straight to the
    /// session it is describing. Nil when there is nothing left to open.
    package let route: Route?
    package let name: String
    package let role: String
    package let provider: AgentKind
    package let running: Bool
    /// Every turn this agent took, kept as its own timestamped slice rather than summed on
    /// the way in — a total cannot be narrowed to the last hour afterwards, and the screen
    /// asks for exactly that.
    package let samples: [UsageSample]

    /// `since` nil is all time; otherwise only what was spent after it.
    func samples(since: Date?) -> [UsageSample] {
        guard let since else { return samples }
        return samples.filter { $0.at >= since }
    }

    func models(since: Date?) -> [String: TokenTally] {
        samples(since: since).reduce(into: [:]) {
            $0[$1.model, default: TokenTally()] = $0[$1.model, default: TokenTally()] + $1.tally
        }
    }

    package func tally(since: Date?) -> TokenTally {
        samples(since: since).map(\.tally).reduce(TokenTally(), +)
    }

    /// The one model to show on a one-line row: whichever spent the most in the window.
    package func topModel(since: Date?) -> String? {
        models(since: since).max { $0.value.total < $1.value.total }?.key
    }

    var lastActive: Date? { samples.last?.at }
}

/// One turn's spend and when it happened. Each supported CLI stamps every record it writes, which
/// is what makes a window and a histogram possible at all.
package struct UsageSample: Sendable {
    let at: Date
    let model: String
    let tally: TokenTally
}

/// The window the usage screen is showing. Wider windows get wider buckets, so the
/// histogram is always about the same number of bars however far back it reaches.
package enum UsageRange: String, CaseIterable, Identifiable {
    case hour = "1h"
    case day = "24h"
    case week = "7d"
    case all = "All"

    package var id: Self { self }

    /// Nil for all time — there is no start to filter against.
    package func since(now: Date = Date()) -> Date? {
        switch self {
        case .hour: return now.addingTimeInterval(-3_600)
        case .day: return now.addingTimeInterval(-86_400)
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .all: return nil
        }
    }

    package var caption: String {
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
package struct UsageBucket: Identifiable {
    package let id: Int
    package let start: Date
    package let byModel: [String: Int]

    package var total: Int { byModel.values.reduce(0, +) }
}

/// One rate-limit window a provider reports — the 5-hour session and the weekly bar both
/// CLIs draw, plus whatever per-model windows the plan carries.
package struct PlanWindow: Identifiable, Sendable {
    package let id: String
    package let name: String
    /// 0–100, as both providers report it.
    package let percent: Double
    package let resetsAt: Date?
}

/// What one coding tool says about the plan behind it. Read from that tool's own cache on
/// disk — neither exposes an API for this, so an unread field just leaves the card empty
/// rather than breaking anything.
package struct ProviderQuota: Sendable {
    package let provider: AgentKind
    package var plan: String?
    package var windows: [PlanWindow] = []
    /// What is on the meter beyond the plan, already worded by the provider that reported
    /// it — Claude meters what has been spent, Codex what is left, and one number labelled
    /// two ways would be a lie half the time.
    package var credits: (label: String, value: String)?
    /// When the numbers were written. Both caches are refreshed by the CLI, not by this
    /// app, so a quiet tool shows a stale bar and has to say so.
    package var asOf: Date?
}

package enum AgentUsage {

    // MARK: - Per-agent spend

    /// A session's role, for the panel that groups spend by one. The console names a
    /// session after what it started it for — "Product", "New Agent" — and numbers the second
    /// of each, so the first word is the role and the number is not. An assigned session is
    /// named after its task, which says nothing about its role, so it is all "work". A
    /// subagent needs none of this: it already carries its agent type.
    static func role(of session: CodeSession) -> String {
        guard !session.holdsTasks else { return "work" }
        return session.title.split(separator: " ").first.map { $0.lowercased() } ?? "session"
    }

    /// Every agent in the project with something on disk to read, biggest spender first.
    package static func spends(in project: Project) async -> [AgentSpend] {
        var spends: [AgentSpend] = []
        // A service terminal is not an agent and spends nothing.
        for session in project.sessions {
            guard let kind = session.agent else { continue }
            let provider = kind.provider
            if let url = await provider.usageURL(session: session.id, project: project.directory) {
                spends.append(
                    AgentSpend(
                        id: session.id.uuidString, route: .session(session.id),
                        name: session.title, role: role(of: session),
                        provider: kind, running: !session.exited,
                        samples: await provider.usage(at: url)))
            }
            for subagent in session.subagents {
                // Scoped to its session: a provider's agent id is unique within the session
                // that spawned it and not beyond, so two sessions can hold the same one —
                // which would collide as a list key here and as a ledger row on disk.
                spends.append(
                    AgentSpend(
                        id: "\(session.id.uuidString):\(subagent.id)",
                        route: .subagent(session: session.id, id: subagent.id),
                        name: subagent.description, role: subagent.agentType,
                        provider: kind, running: subagent.running,
                        samples: await provider.usage(at: subagent.transcriptURL)))
            }
        }
        return spends.filter { !$0.samples.isEmpty }
    }

    /// Sums a keyed slice of the spends — by role, by provider — as one call, because
    /// those panels are the same fold over a different key.
    package static func group<Key: Hashable>(
        _ spends: [AgentSpend], since: Date?,
        by key: (AgentSpend) -> Key
    ) -> [(key: Key, tally: TokenTally)] {
        Dictionary(grouping: spends, by: key)
            .map { (key: $0.key, tally: $0.value.map { $0.tally(since: since) }.reduce(TokenTally(), +)) }
            .filter { $0.tally.total > 0 }
            .sorted { $0.tally.total > $1.tally.total }
    }

    package static func byModel(_ spends: [AgentSpend], since: Date?) -> [(key: String, tally: TokenTally)] {
        spends.flatMap { $0.samples(since: since) }
            .reduce(into: [String: TokenTally]()) {
                $0[$1.model, default: TokenTally()] = $0[$1.model, default: TokenTally()] + $1.tally
            }
            .map { (key: $0.key, tally: $0.value) }
            .filter { $0.tally.total > 0 }
            .sorted { $0.tally.total > $1.tally.total }
    }

    /// The histogram: the range sliced into equal buckets, each holding what every model
    /// spent inside it. Samples outside the range fall outside the bucket index and are
    /// dropped here rather than filtered first.
    package static func histogram(
        _ samples: [UsageSample], range: UsageRange,
        now: Date = Date()
    ) -> [UsageBucket] {
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
            UsageBucket(
                id: $0.offset, start: start.addingTimeInterval(width * Double($0.offset)),
                byModel: $0.element)
        }
    }

    /// One JSONL line as an object, or nil for anything else.
    static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Plan limits

    /// Claude Code caches what the API told it about the plan in `~/.claude.json`, and
    /// refreshes it as it works. Nothing here is a published API, so a missing field
    /// leaves a bar out instead of failing.
    package static func claudeQuota(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    ) async -> ProviderQuota? {
        guard let data = try? Data(contentsOf: configURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cached = root["cachedUsageUtilization"] as? [String: Any],
            let utilization = cached["utilization"] as? [String: Any]
        else { return nil }

        var quota = ProviderQuota(
            provider: .claude,
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
                let percent = (window["utilization"] as? NSNumber)?.doubleValue
            else { return nil }
            return PlanWindow(
                id: key, name: name, percent: percent,
                resetsAt: date(window["resets_at"] as? String))
        }
        if let spend = utilization["spend"] as? [String: Any],
            let used = money(spend["used"] as? [String: Any] ?? [:]),
            let limit = money(spend["limit"] as? [String: Any] ?? [:])
        {
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
    package static func codexQuota(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) async -> ProviderQuota? {
        let root = codexHome.appendingPathComponent("sessions")
        guard
            let walk = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])
        else { return nil }
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
                        let percent = (window["used_percent"] as? NSNumber)?.doubleValue
                    else { return nil }
                    let resets = (window["resets_at"] as? NSNumber)?.doubleValue
                    return PlanWindow(
                        id: key, name: name, percent: percent,
                        resetsAt: resets.map { Date(timeIntervalSince1970: $0) })
                }
            // Only when the account actually has credits: a zero balance on an account
            // that never bought any is not a fact worth a row.
            if let credits = limits["credits"] as? [String: Any],
                credits["has_credits"] as? Bool == true
            {
                quota.credits = (
                    "Credits left",
                    credits["unlimited"] as? Bool == true
                        ? "unlimited"
                        : "$\(credits["balance"] as? String ?? "0")"
                )
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
    package static func short(_ count: Int) -> String {
        switch count {
        case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
        case 10_000...: return "\(count / 1000)K"
        case 1_000...: return String(format: "%.1fK", Double(count) / 1000)
        default: return "\(count)"
        }
    }

    /// How long ago something was written. A quota is only as fresh as the last turn that
    /// wrote it, so a tool that has been quiet all day has to say so rather than look current.
    package static func ago(_ date: Date, now: Date = Date()) -> String {
        span(now.timeIntervalSince(date)).map { "\($0) ago" } ?? "just now"
    }

    /// "2h 14m", "6d", or nil once the window has already rolled over.
    package static func until(_ date: Date?, now: Date = Date()) -> String? {
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

    package static func family(_ model: String) -> String {
        let name = model.lowercased()
        return ["opus", "sonnet", "haiku", "fable", "gpt", "codex"].first { name.contains($0) } ?? "other"
    }

    /// `claude-haiku-4-5-20251001` → `haiku-4-5`: the date stamp is noise in a legend.
    package static func modelName(_ model: String) -> String {
        let stripped = model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
        let parts = stripped.split(separator: "-")
        guard let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) else { return stripped }
        return parts.dropLast().joined(separator: "-")
    }
}
