import Foundation
import Testing

@testable import Yongkang

/// The usage screen reads token counts out of the same transcripts the console
/// watches. Both providers write them differently — Claude a delta per message, Codex
/// a running total — and the Claude side is read incrementally, so a second pass over
/// a file that grew must add the new lines and not re-count the old ones.
///
/// Serialized: `AgentUsage.samples` keeps a per-file cursor in an unsynchronised
/// `static var`. Every test reads transcripts under its own temporary folder, so no
/// cursor an earlier test left can match one of its files.
@Suite(.serialized) struct UsageTests {

    private func at(_ clock: String) -> Date { AgentUsage.date("2026-09-03T\(clock):00.000Z")! }
    private var noon: Date { at("12:00") }

    /// The four lines of `usage/claude-session-usage.jsonl`: opus 12:00, opus 12:30,
    /// haiku 12:45, opus 12:50.
    private func claudeLines() throws -> [String] {
        try fixture("usage/claude-session-usage.jsonl").split(separator: "\n").map(String.init)
    }

    /// The first three Claude turns, read the way the screen reads them.
    private func grownSamples(in dir: URL) throws -> (transcript: URL, samples: [UsageSample]) {
        let lines = try claudeLines()
        let transcript = dir.appendingPathComponent("session.jsonl")
        try (lines[0...2].joined(separator: "\n") + "\n").write(to: transcript, atomically: true, encoding: .utf8)
        return (transcript, AgentUsage.samples(at: transcript, .claude))
    }

    private func rolloutSamples(in dir: URL) throws -> [UsageSample] {
        let codex = dir.appendingPathComponent("rollout.jsonl")
        try fixture("usage/codex-rollout-token-count.jsonl").write(to: codex, atomically: true, encoding: .utf8)
        return AgentUsage.samples(at: codex, .codex)
    }

    private func leadSpend(_ samples: [UsageSample]) -> AgentSpend {
        AgentSpend(id: "s", tag: "t", name: "Lead", role: "lead", provider: .claude, running: true, samples: samples)
    }

    @Test func claudeTranscriptIsReadIncrementally() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = try claudeLines()
        let claude = dir.appendingPathComponent("session.jsonl")

        try (lines[0] + "\n").write(to: claude, atomically: true, encoding: .utf8)
        let first = AgentUsage.samples(at: claude, .claude)
        try #require(first.count == 1)
        #expect(first[0].at == noon)
        #expect(first[0].tally.output == 5)
        #expect(first[0].tally.cacheRead == 100)
        #expect(first[0].tally.total == 135)

        // Appended while the screen is open: the second read must pick up only the new lines.
        try append(lines[1] + "\n" + lines[2] + "\n", to: claude)
        let grown = AgentUsage.samples(at: claude, .claude)
        #expect(grown.count == 3, "an appended transcript is not re-counted")
        #expect(grown.filter { $0.model == "claude-opus-5" }.map(\.tally.output).reduce(0, +) == 10)

        // A half-written last line is left for the next pass rather than parsed as garbage.
        try append(String(lines[3].prefix(40)), to: claude)
        #expect(
            AgentUsage.samples(at: claude, .claude).count == 3,
            "a partial line is not counted until its newline lands")
    }

    // Windowing is what the range picker does: the same samples, narrowed by time.
    @Test func spendNarrowsToTheWindow() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spend = leadSpend(try grownSamples(in: dir).samples)

        #expect(spend.tally(since: nil).total == 403, "all time is every sample")
        #expect(spend.samples(since: at("12:40")).count == 1, "and a window is only what fits")
        #expect(spend.models(since: at("12:40")).keys.first == "claude-haiku-4-5-20251001")
        #expect(
            spend.topModel(since: nil) == "claude-opus-5",
            "the model on a row is the one that spent most in the window")
    }

    @Test func codexRunningTotalsBecomeSteps() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rollout = try rolloutSamples(in: dir)

        try #require(rollout.count == 2, "a repeated running total is not a second turn")
        #expect(rollout.allSatisfy { $0.model == "gpt-5.6-luna" }, "the model comes off turn_context")
        // Differencing telescopes: the samples add back to the last total the file reported.
        let summed = rollout.map(\.tally).reduce(TokenTally(), +)
        let telescoped: Comment = "Codex reports a running total, and its input already includes the cached half"
        #expect(summed.output == 40, telescoped)
        #expect(summed.cacheRead == 250, telescoped)
        #expect(summed.input == 50, telescoped)
        #expect(rollout[1].tally.output == 35, "so a sample is the step, not the total")
    }

    // The histogram slices the range into equal buckets and drops nothing inside it.
    @Test func histogramBucketsEverySampleOnce() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let grown = try grownSamples(in: dir).samples
        let noonish = grown + (try rolloutSamples(in: dir))

        let hour = AgentUsage.histogram(noonish, range: .hour, now: at("13:00"))
        try #require(hour.count == UsageRange.hour.buckets)
        #expect(
            hour.map(\.total).reduce(0, +) == noonish.map(\.tally.total).reduce(0, +),
            "every sample inside the range lands in exactly one bucket")
        #expect(hour[0].byModel["claude-opus-5"] == 135, "and lands in the right one")
        #expect(hour[6].byModel["claude-opus-5"] == 135)
        #expect(hour[9].byModel["claude-haiku-4-5-20251001"] == 133)
        let stale = AgentUsage.histogram(noonish, range: .hour, now: at("18:00"))
        #expect(stale.map(\.total).reduce(0, +) == 0, "and nothing older than the range shows at all")
        // A sample landing on the window's own edge belongs in the last bucket, not nowhere.
        let edge = AgentUsage.histogram(
            [UsageSample(at: at("13:00"), model: "m", tally: grown[0].tally)],
            range: .hour, now: at("13:00"))
        #expect(edge.last?.total == 135)
        #expect(
            AgentUsage.histogram([], range: .all, now: noon).isEmpty,
            "an all-time view of nothing draws no bars rather than dividing by zero")
    }

    // The ledger is what makes the numbers outlive the app: sessions are not restored
    // on relaunch, so without it a reopened project shows nothing however much its
    // agents spent.
    @Test func ledgerIsOnlyWrittenIntoANotebook() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spend = leadSpend(try grownSamples(in: dir).samples)
        let notebook = dir.appendingPathComponent(".notebook")

        #expect(
            !UsageLedger.record([spend], root: notebook),
            "a project with no notebook is not given one just to file usage in")
        try FileManager.default.createDirectory(at: notebook, withIntermediateDirectories: true)
        #expect(UsageLedger.record([spend], root: notebook))
        #expect(
            !UsageLedger.record([spend], root: notebook),
            "and an unchanged ledger is not rewritten, because the poll calls this")
    }

    @Test func ledgerRemembersSpendByTheHour() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spend = leadSpend(try grownSamples(in: dir).samples)
        let notebook = try makeNotebook(in: dir)
        UsageLedger.record([spend], root: notebook)

        let remembered = UsageLedger.load(root: notebook)
        try #require(remembered.count == 1)
        #expect(remembered[0].id == spend.id)
        #expect(remembered[0].name == "Lead")
        #expect(remembered[0].role == "lead")
        #expect(
            remembered[0].tally(since: nil).total == spend.tally(since: nil).total,
            "what an agent spent survives the run that read it")
        #expect(remembered[0].tag.isEmpty, "but its session is gone, so nothing opens")
        // 12:00 and 12:30 are one opus hour; 12:45 is a haiku hour of its own.
        #expect(remembered[0].samples.count == 2, "kept by the hour, not by the turn")
        #expect(
            remembered[0].samples.allSatisfy {
                $0.at.timeIntervalSince1970.truncatingRemainder(dividingBy: 3_600) == 0
            }, "and filed on the hour mark")
    }

    // Usage only accumulates, so a re-read that comes back short — a truncated or
    // rotated transcript — must not erase the hour it had already recorded.
    @Test func shortReReadKeepsTheFullerRecord() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let grown = try grownSamples(in: dir).samples
        let spend = leadSpend(grown)
        let notebook = try makeNotebook(in: dir)
        UsageLedger.record([spend], root: notebook)

        let truncated = AgentSpend(
            id: spend.id, tag: "t", name: "Lead", role: "lead",
            provider: .claude, running: false, samples: [grown[0]])
        UsageLedger.record([truncated], root: notebook)
        #expect(
            UsageLedger.load(root: notebook).first?.tally(since: nil).total
                == spend.tally(since: nil).total, "a short re-read keeps the fuller record")
    }

    // A provider's agent id is only unique inside the session that spawned it, so the
    // spend that carries it has to be scoped — it is both a list key and a ledger row,
    // and two sessions really do hand out the same one.
    //
    // The two leads' own transcripts are looked up under the real `~/.claude/projects/`
    // (`spends(in:)` has no home override). Read-only, for random session ids that cannot exist.
    @Test func sameAgentIDUnderTwoLeadsIsTwoRows() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let claude = try grownSamples(in: dir).transcript

        let shared = SubagentStatus(
            id: "a3a603000d158ff03", description: "qa", agentType: "qa-dev",
            running: false, transcriptURL: claude)
        var twin = Project(directory: dir, entries: [])
        twin.sessions = [
            CodeSession(
                id: UUID(), title: "Engineering Lead", icon: "s", line: "claude",
                agent: .claude, subagents: [shared]),
            CodeSession(
                id: UUID(), title: "Engineering Lead 2", icon: "s", line: "claude",
                agent: .claude, subagents: [shared]),
        ]
        let ids = AgentUsage.spends(in: twin).map(\.id)
        #expect(ids.count == 2, "both leads' copies of the agent have spend to show")
        #expect(Set(ids).count == ids.count, "the same agent id under two leads is two rows")
    }

    // A second agent joins the ledger rather than replacing the first.
    @Test func secondAgentJoinsTheLedger() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let notebook = try makeNotebook(in: dir)
        UsageLedger.record([leadSpend(try grownSamples(in: dir).samples)], root: notebook)

        let other = AgentSpend(
            id: "codex-1", tag: "t", name: "Backend", role: "backend-dev",
            provider: .codex, running: false, samples: try rolloutSamples(in: dir))
        UsageLedger.record([other], root: notebook)
        let both = UsageLedger.load(root: notebook)
        #expect(both.count == 2, "and each agent keeps its own provider")
        #expect(both.contains { $0.provider == .codex }, "and each agent keeps its own provider")
    }

    // MARK: - A damaged ledger (trust boundary)
    //
    // `usage.json` sits in a folder people commit and agents write into, so it can come back
    // cut short by a crash or replaced by something that is not a ledger at all.

    enum Damage: CaseIterable { case truncated, notJSON }

    @Test(arguments: Damage.allCases)
    func damagedLedgerReadsAsNothing(_ damage: Damage) throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let notebook = try makeNotebook(in: dir)
        let damaged = try damageLedger(damage, in: notebook, samples: try grownSamples(in: dir).samples)

        #expect(UsageLedger.load(root: notebook).isEmpty, "an unreadable ledger reads as no rows, not a crash")
        #expect(try Data(contentsOf: UsageLedger.url(root: notebook)) == damaged, "and reading it changes nothing")
    }

    @Test(arguments: Damage.allCases)
    func damagedLedgerIsNotOverwritten(_ damage: Damage) throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let notebook = try makeNotebook(in: dir)
        let damaged = try damageLedger(damage, in: notebook, samples: try grownSamples(in: dir).samples)

        let other = AgentSpend(
            id: "codex-1", tag: "t", name: "Backend", role: "backend-dev",
            provider: .codex, running: false, samples: try rolloutSamples(in: dir))
        UsageLedger.record([other], root: notebook)
        // Compared as text so a failure shows what the file became, not a byte dump.
        let after = try String(contentsOf: UsageLedger.url(root: notebook), encoding: .utf8)
        withKnownIssue(
            "UsageLedger.record treats an unreadable usage.json as empty and replaces it, so the hours it held are lost"
        ) {
            #expect(
                after == String(decoding: damaged, as: UTF8.self),
                "a ledger that cannot be read is left for a person to recover, not written over")
        }
    }

    /// Records a real ledger for the lead, then damages the file. Returns the damaged bytes.
    private func damageLedger(_ damage: Damage, in notebook: URL, samples: [UsageSample]) throws -> Data {
        UsageLedger.record([leadSpend(samples)], root: notebook)
        let url = UsageLedger.url(root: notebook)
        let written = try Data(contentsOf: url)
        let damaged =
            switch damage {
            case .truncated: written.prefix(written.count / 2)
            case .notJSON: Data("not a ledger\n".utf8)
            }
        try damaged.write(to: url)
        return damaged
    }

    private func makeNotebook(in dir: URL) throws -> URL {
        let notebook = dir.appendingPathComponent(".notebook")
        try FileManager.default.createDirectory(at: notebook, withIntermediateDirectories: true)
        return notebook
    }

    // MARK: - Plan limits and formatting

    // Plan limits come out of Claude Code's own config cache, which is not an API —
    // a shape it does not recognise has to read as "nothing to show", never as a crash.
    @Test func claudeQuotaFromTheConfigCache() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("claude.json")
        try fixture("usage/claude-config-cached-usage.json").write(to: config, atomically: true, encoding: .utf8)

        let quota = try #require(AgentUsage.claudeQuota(configURL: config))
        #expect(quota.plan == "claude_pro")
        try #require(quota.windows.map(\.percent) == [42, 3], "a null window is skipped, not zeroed")
        #expect(quota.windows[0].resetsAt != nil, "the ISO shape with fractional seconds parses")
        #expect(quota.windows[1].resetsAt != nil, "and the one without")
        #expect(quota.credits?.value == "$2.50 of $100.00")
        #expect(AgentUsage.claudeQuota(configURL: dir.appendingPathComponent("nope.json")) == nil)
    }

    @Test(arguments: [(999, "999"), (1_500, "1.5K"), (45_000, "45K"), (2_400_000, "2.4M")])
    func shortCount(count: Int, text: String) {
        #expect(AgentUsage.short(count) == text)
    }

    @Test(arguments: [("claude-haiku-4-5-20251001", "haiku-4-5"), ("gpt-5.6-luna", "gpt-5.6-luna")])
    func modelName(model: String, name: String) {
        #expect(AgentUsage.modelName(model) == name)
    }

    // Two versions of one model must not draw as the same colour, or a stacked bar
    // says how much went to Opus without saying which Opus.
    @Test func paletteShadesVersionsOfOneFamily() {
        let shades = AgentUsage.palette(for: ["claude-opus-5", "claude-opus-4-7", "claude-sonnet-5"])
        #expect(shades["claude-opus-5"] != shades["claude-opus-4-7"])
        #expect(
            shades["claude-opus-5"] == AgentUsage.modelTint("claude-opus-5"),
            "and the biggest spender in a family keeps the family's own colour")
    }

    @Test func untilAWindowResets() {
        #expect(AgentUsage.until(noon.addingTimeInterval(8_100), now: noon) == "2h 15m")
        #expect(
            AgentUsage.until(noon.addingTimeInterval(-60), now: noon) == nil,
            "a window that already rolled over says nothing rather than a negative")
    }

    /// Writes to the end of a file the way an agent's transcript grows: open, seek, write.
    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
