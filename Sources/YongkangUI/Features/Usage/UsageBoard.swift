import SwiftUI
import YongkangCore

/// What the agents are costing, in one screen: how close each coding tool is to its plan
/// limit, which models the spend went to, which role spent it, and which individual agent.
/// Every number is read off the same transcripts the rest of the console watches, so this
/// screen keeps no state of its own to drift out of date.
package struct UsageBoard: View {
    let project: Project
    let open: (String) -> Void

    /// Loaded on a change rather than per render: parsing transcripts inside `body` at
    /// 60fps would be the most expensive thing in the app.
    @State private var spends: [AgentSpend] = []
    @State private var quotas: [ProviderQuota] = []
    /// How far back every panel below the plan limits is counting. 24 hours by default:
    /// a day is the span a person actually remembers working, and all time on a machine
    /// that has been running agents for months answers a different question.
    @State private var range: UsageRange = .day
    /// Pinned when the screen loads rather than read per render, so the window edge and
    /// the histogram's last bucket do not creep while you look at them.
    @State private var now = Date()

    /// `range` is only ever passed by the shot renderer, which has no one to click the
    /// picker and would otherwise photograph whichever window happens to be quiet on the
    /// machine it runs on.
    package init(project: Project, open: @escaping (String) -> Void, range: UsageRange = .day) {
        self.project = project
        self.open = open
        _range = State(initialValue: range)
    }

    private var since: Date? { range.since(now: now) }
    private var windowed: [AgentSpend] {
        spends.filter { $0.tally(since: since).total > 0 }
            .sorted { $0.tally(since: since).total > $1.tally(since: since).total }
    }
    private var total: TokenTally { spends.map { $0.tally(since: since) }.reduce(TokenTally(), +) }

    /// Fixed once per render off the window's own ranking, so the same model is the same
    /// colour in the histogram, the model bar and every agent row below it.
    private var palette: [String: Color] {
        AgentUsage.palette(for: AgentUsage.byModel(spends, since: since).map(\.key))
    }

    private func tint(_ model: String) -> Color { palette[model] ?? AgentUsage.modelTint(model) }

    package var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 20) {
                    limits
                    overTime
                    byModel
                    runs
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 20) {
                    totals
                    byAgent
                    Spacer(minLength: 0)
                }
                .frame(width: 332)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task(id: signature) { load() }
    }

    /// Re-read when an agent appears, finishes, or writes — the sizes of the files this
    /// screen reads are what change as work happens, and a byte more is a token more.
    private var signature: String {
        let ledger =
            (try? UsageLedger.url(root: project.notebookRoot)
                .resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let transcripts = project.sessions.compactMap { Transcripts.usageURL(of: $0, in: project.directory) }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        return project.sessions.map { session in
            session.id.uuidString + session.subagents.map { $0.id + "\($0.running)" }.joined()
        }.joined() + "\(project.sessions.count):\(ledger):\(transcripts)"
    }

    private func load() {
        now = Date()
        // Live agents are read from their transcripts at full resolution; the ledger fills
        // in every earlier run, whose sessions died with the app that started them.
        let live = AgentUsage.spends(in: project)
        let running = Set(live.map(\.id))
        spends = live + UsageLedger.load(root: project.notebookRoot).filter { !running.contains($0.id) }
        quotas = [AgentUsage.claudeQuota(), AgentUsage.codexQuota()].compactMap { $0 }
    }

    // MARK: - Over time

    /// The range picker and the histogram under it. The picker sits here rather than in
    /// the top bar because this is the first panel it governs — the plan limits above are
    /// the provider's own windows and are not ours to re-slice.
    private var overTime: some View {
        let buckets = AgentUsage.histogram(spends.flatMap(\.samples), range: range, now: now)
        let peak = buckets.map(\.total).max() ?? 0
        // Segments stack in the window's overall ranking, not each bucket's own, so a model
        // holds the same band across every bar instead of swapping places between them.
        let order = AgentUsage.byModel(spends, since: since).map(\.key)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionLabel("Usage over time")
                Spacer(minLength: 12)
                Picker("", selection: $range) {
                    ForEach(UsageRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
            }
            if peak == 0 {
                note("Nothing spent in the \(range.caption).")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(buckets) { bar($0, peak: peak, order: order) }
                    }
                    .frame(height: 108)
                    axis(buckets)
                }
                .cardSurface()
            }
        }
    }

    /// One bucket, stacked by model — the tallest bar is the busiest slice of the range,
    /// and the colours inside it are where that work went.
    private func bar(_ bucket: UsageBucket, peak: Int, order: [String]) -> some View {
        let height = 108 * Double(bucket.total) / Double(peak)
        let segments = bucket.byModel.sorted {
            (order.firstIndex(of: $0.key) ?? order.count) < (order.firstIndex(of: $1.key) ?? order.count)
        }
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(segments, id: \.key) { model, count in
                Rectangle().fill(tint(model))
                    .frame(height: max(0, height * Double(count) / Double(bucket.total)))
            }
        }
        .frame(maxWidth: .infinity)
        // Rounded at the top only, so a stack of segments still reads as one bar.
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .help("\(stamp(bucket.start)) · \(AgentUsage.short(bucket.total))")
    }

    /// Three marks rather than one per bar: the range is the axis, and a label under every
    /// bucket would be unreadable at 12 buckets and absurd at 32.
    private func axis(_ buckets: [UsageBucket]) -> some View {
        HStack(spacing: 0) {
            ForEach(
                [buckets.first, buckets[buckets.count / 2], buckets.last].compactMap { $0 },
                id: \.id
            ) { bucket in
                Text(stamp(bucket.start)).font(Typo.mono(9.5)).foregroundStyle(Theme.tx4)
                    .frame(
                        maxWidth: .infinity,
                        alignment: bucket.id == 0
                            ? .leading
                            : (bucket.id == buckets.last?.id ? .trailing : .center))
            }
        }
    }

    /// An hour needs a clock, a week needs a date — a bucket labelled 14:00 across seven
    /// days says nothing about which day.
    private func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = range == .hour || range == .day ? "HH:mm" : "d MMM"
        return formatter.string(from: date)
    }

    // MARK: - Plan limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Plan limits", trailing: "read from each CLI's own cache")
            if quotas.isEmpty {
                note(
                    "No plan limits on disk yet. Both CLIs write these as they work — run "
                        + "an agent and they appear.")
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(quotas, id: \.provider) { quotaCard($0) }
                }
            }
        }
    }

    private func quotaCard(_ quota: ProviderQuota) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: quota.provider.systemImage)
                    .font(.system(size: 11)).foregroundStyle(Theme.tx2)
                Text(quota.provider.displayName).font(Typo.display(13))
                if let plan = quota.plan {
                    NotebookStyle.chip(plan.replacingOccurrences(of: "_", with: " "))
                }
                Spacer(minLength: 8)
                if let asOf = quota.asOf {
                    Text(AgentUsage.ago(asOf)).font(Typo.mono(9.5)).foregroundStyle(Theme.tx4)
                }
            }
            if quota.windows.isEmpty {
                Text("No windows reported.").font(Typo.text(12)).foregroundStyle(Theme.tx3)
            } else {
                ForEach(quota.windows) { window($0) }
            }
            if let credits = quota.credits {
                Divider().overlay(Theme.line)
                HStack(spacing: 6) {
                    Text(credits.label).font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                    Spacer(minLength: 8)
                    Text(credits.value).font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func window(_ window: PlanWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(window.name).font(Typo.text(11.5)).foregroundStyle(Theme.tx2)
                Spacer(minLength: 8)
                if let until = AgentUsage.until(window.resetsAt) {
                    Text("resets in \(until)").font(Typo.mono(10)).foregroundStyle(Theme.tx4)
                }
                Text("\(Int(window.percent.rounded()))%")
                    .font(Typo.mono(11, .semibold))
                    .foregroundStyle(AgentUsage.tint(window.percent))
            }
            MeterBar(value: window.percent / 100, tint: AgentUsage.tint(window.percent), height: 5)
        }
    }

    // MARK: - By model

    private var byModel: some View {
        let rows = AgentUsage.byModel(spends, since: since)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("By model", trailing: range.caption)
            if rows.isEmpty {
                note("Nothing spent in the \(range.caption).")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // One bar for the whole project, split by model — the share each model
                    // took is the question, and separate bars would not answer it.
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(rows, id: \.key) { row in
                                Capsule().fill(tint(row.key))
                                    .frame(
                                        width: max(
                                            2,
                                            geo.size.width
                                                * Double(row.tally.total)
                                                / Double(max(1, total.total))))
                            }
                        }
                    }
                    .frame(height: 8)
                    ForEach(rows, id: \.key) { modelRow($0.key, $0.tally) }
                }
                .cardSurface()
            }
        }
    }

    private func modelRow(_ model: String, _ tally: TokenTally) -> some View {
        HStack(spacing: 10) {
            Circle().fill(tint(model)).frame(width: 7, height: 7)
            Text(AgentUsage.modelName(model)).font(Typo.mono(11.5)).foregroundStyle(Theme.tx)
            Text("\(share(tally))%").font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            Spacer(minLength: 12)
            splitLabels(tally)
            Text(AgentUsage.short(tally.total))
                .font(Typo.mono(11.5, .semibold)).foregroundStyle(Theme.tx)
                .frame(width: 56, alignment: .trailing)
        }
    }

    /// The three numbers behind a total, in the order they cost: what was written, what was
    /// sent fresh, and what the cache already held.
    private func splitLabels(_ tally: TokenTally) -> some View {
        HStack(spacing: 10) {
            ForEach(
                [
                    ("out", tally.output), ("in", tally.input),
                    ("cache", tally.cacheRead + tally.cacheWrite),
                ], id: \.0
            ) { label, value in
                Text("\(label) \(AgentUsage.short(value))")
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            }
        }
    }

    // MARK: - Every run

    /// One row per run — a session, or one dispatch of a specialist. The panel beside it
    /// sums these by who they belong to; this is the list you click through to a transcript.
    private var runs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Agent runs", trailing: range.caption)
            if windowed.isEmpty {
                note(
                    spends.isEmpty
                        ? "No agent has a transcript on disk yet. Assign work on the board and "
                            + "the lead's specialists show up here as they run."
                        : "No agent spent anything in the \(range.caption).")
            } else {
                VStack(spacing: 0) {
                    ForEach(windowed) { agentRow($0) }
                }
                .cardSurface(padding: 6)
            }
        }
    }

    private func agentRow(_ spend: AgentSpend) -> some View {
        Button {
            open(spend.tag)
        } label: {
            HStack(spacing: 10) {
                RoleTile(role: spend.role, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(person(spend)).font(Typo.text(12.5)).foregroundStyle(Theme.tx).lineLimit(1)
                        if spend.running { StateDot(live: true) }
                    }
                    HStack(spacing: 6) {
                        // The run's own label, when it says more than the name above does —
                        // which dispatch of a specialist this row is.
                        if spend.name != person(spend) {
                            Text(spend.name).font(Typo.mono(9.5)).foregroundStyle(Theme.tx4)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        if let model = spend.topModel(since: since) {
                            Text(AgentUsage.modelName(model))
                                .font(Typo.mono(9.5)).foregroundStyle(tint(model))
                        }
                        Text(spend.provider.displayName).font(Typo.mono(9.5)).foregroundStyle(Theme.tx4)
                    }
                }
                Spacer(minLength: 12)
                MeterBar(value: fraction(spend.tally(since: since)), tint: RoleTile.color(of: spend.role))
                    .frame(width: 90)
                Text(AgentUsage.short(spend.tally(since: since).total))
                    .font(Typo.mono(11.5, .semibold)).foregroundStyle(Theme.tx)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(spend.tag.isEmpty)
    }

    // MARK: - Totals and roles

    private var totals: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("This project", trailing: range.caption)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AgentUsage.short(total.total)).font(Typo.display(26))
                    Text("tokens").font(Typo.text(12)).foregroundStyle(Theme.tx3)
                }
                ForEach(
                    [
                        ("Output", total.output), ("Input", total.input),
                        ("Cache write", total.cacheWrite), ("Cache read", total.cacheRead),
                    ],
                    id: \.0
                ) { label, value in
                    HStack(spacing: 8) {
                        Text(label).font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                        Spacer(minLength: 8)
                        Text(AgentUsage.short(value)).font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                    }
                }
                Divider().overlay(Theme.line)
                HStack(spacing: 8) {
                    Text("Cache hit rate").font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                    Spacer(minLength: 8)
                    Text("\(Int((total.cacheRate * 100).rounded()))%")
                        .font(Typo.mono(11)).foregroundStyle(Theme.green)
                }
                HStack(spacing: 8) {
                    Text("Agents").font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                    Spacer(minLength: 8)
                    Text("\(windowed.filter(\.running).count) running · \(windowed.count) active")
                        .font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    /// Spend by who it belongs to rather than by which run spent it: a specialist
    /// dispatched five times is one member of the team spending five times, and their name
    /// is the number worth reading. Split by provider underneath, because the same agent
    /// runs under either CLI and the two plans are metered apart.
    private var byAgent: some View {
        let rows = AgentUsage.group(windowed, since: since, by: person)
        // Ranked against the biggest spender here, not the biggest single run — a person's
        // bar has to be able to reach the end of the track.
        let peak = rows.first?.tally.total ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("By agent", trailing: range.caption)
            if rows.isEmpty {
                note("Nothing spent in the \(range.caption).")
            } else {
                VStack(spacing: 13) {
                    ForEach(rows, id: \.key) { agentGroup($0.key, $0.tally, peak: peak) }
                }
                .cardSurface()
            }
        }
    }

    private func agentGroup(_ name: String, _ tally: TokenTally, peak: Int) -> some View {
        let mine = windowed.filter { person($0) == name }
        // Off the skill, not the name: renaming an agent never changes its colour.
        let role = mine.first?.role ?? name
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                RoleTile(role: role, size: 20)
                Text(name).font(Typo.text(12)).foregroundStyle(Theme.tx).lineLimit(1)
                Text("\(mine.count)").font(Typo.mono(10)).foregroundStyle(Theme.tx4)
                Spacer(minLength: 8)
                Text(AgentUsage.short(tally.total))
                    .font(Typo.mono(11, .semibold)).foregroundStyle(Theme.tx2)
            }
            MeterBar(
                value: peak == 0 ? 0 : Double(tally.total) / Double(peak),
                tint: RoleTile.color(of: role))
            ForEach(AgentUsage.group(mine, since: since, by: \.provider), id: \.key) { row in
                HStack(spacing: 7) {
                    Image(systemName: row.key.systemImage)
                        .font(.system(size: 9)).foregroundStyle(Theme.tx4).frame(width: 11)
                    Text(row.key.displayName).font(Typo.text(11)).foregroundStyle(Theme.tx3)
                    Spacer(minLength: 8)
                    Text(AgentUsage.short(row.tally.total))
                        .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                }
                .padding(.leading, 29)
            }
        }
    }

    /// Whose spend a run is. A specialist is the team member whose skill it ran; a session
    /// is itself, except a lead — the console numbers a second one, and both are the lead.
    private func person(_ spend: AgentSpend) -> String {
        if spend.role == AgentUsage.leadRole { return "Engineering Lead" }
        return Team.running(spend.role, in: project.team)?.member.name ?? spend.name
    }

    // MARK: - Shared

    /// Every bar on this screen is a share of the project's own spend, so the widest one is
    /// always full — the comparison is between agents, not against an absolute nobody knows.
    private func fraction(_ tally: TokenTally) -> Double {
        let top = windowed.first?.tally(since: since).total ?? 0
        return top == 0 ? 0 : Double(tally.total) / Double(top)
    }

    private func share(_ tally: TokenTally) -> Int {
        total.total == 0 ? 0 : Int((Double(tally.total) / Double(total.total) * 100).rounded())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}
