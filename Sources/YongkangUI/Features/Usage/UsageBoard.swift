import SwiftUI
import YongkangCore

/// What the agents are costing, across every open project, in one screen: how close each coding
/// tool is to its plan limit — which is the whole machine's, not a project's — which project and
/// which models the spend went to, which role spent it, and which individual agent. Every number
/// is read off the same transcripts the rest of the console watches, so this screen keeps no
/// state of its own to drift out of date.
package struct UsageBoard: View {
    let projects: [Project]
    /// What the files this screen reads looked like at the last read of each project: its
    /// sessions and subagents, and the sizes of the transcripts and the ledger their spend is
    /// parsed out of. A byte more is a token more, so a change here is something new to show.
    ///
    /// It arrives from each `ProjectModel`, which has it from the same FSEvents-driven read as
    /// everything else on screen (`ProjectReader.watch(of:)`). This screen used to `stat` those
    /// files itself every two seconds; the folders they sit in are exactly the ones the
    /// projects' watchers watch, so the beat that reloads the console reloads this too.
    let signature: String
    /// Opens a run: the project it was in, and the route to it there.
    let open: (Project.ID, Route) -> Void

    /// Loaded on a change rather than per render: parsing transcripts inside `body` at
    /// 60fps would be the most expensive thing in the app.
    @State private var spends: [AgentSpend] = []
    /// Which project each run was in, by the run's id.
    @State private var owners: [AgentSpend.ID: Project.ID] = [:]
    @State private var quotas: [ProviderQuota] = []
    /// How far back the panels under the plan limits count. 24 hours by default:
    /// a day is the span a person actually remembers working, and all time on a machine
    /// that has been running agents for months answers a different question.
    @State private var range: UsageRange = .day
    @State private var breakdown: Breakdown = .project
    /// Pinned when the screen loads rather than read per render, so the window edge and
    /// the histogram's last bucket do not creep while you look at them.
    @State private var now = Date()

    /// `range` is only ever passed by the shot renderer, which has no one to click the
    /// picker and would otherwise photograph whichever window happens to be quiet on the
    /// machine it runs on.
    package init(
        projects: [Project], signature: String = "", open: @escaping (Project.ID, Route) -> Void,
        range: UsageRange = .day
    ) {
        self.projects = projects
        self.signature = signature
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
            VStack(alignment: .leading, spacing: 22) {
                limits
                HStack(alignment: .top, spacing: 20) {
                    spent.frame(maxWidth: .infinity)
                    whereItWent.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task(id: signature) { await load() }
    }

    private func load() async {
        // Limits first: they are the screen's first question, and a busy day's transcripts
        // take seconds to parse — the top of the screen should not wait on the bottom.
        quotas = await AgentUsage.quotas(claudeLive: await ClaudeLimits.shared.usage())
        var found: [AgentSpend] = []
        var owned: [AgentSpend.ID: Project.ID] = [:]
        for project in projects {
            // Live agents are read from their transcripts at full resolution; the ledger fills
            // in every earlier run, whose sessions died with the app that started them.
            let live = await AgentUsage.spends(in: project)
            let running = Set(live.map(\.id))
            let remembered = await UsageLedger.load(root: project.notebookRoot)
            let runs = live + remembered.filter { !running.contains($0.id) }
            for run in runs { owned[run.id] = project.id }
            found += runs
        }
        now = Date()
        spends = found
        owners = owned
    }

    // MARK: - Spent

    /// The total for the range, and when in the range it was spent. The range picker sits
    /// here rather than in the toolbar because this is the first panel it governs — the plan
    /// limits above are the provider's own windows and are not ours to re-slice.
    private var spent: some View {
        let buckets = AgentUsage.histogram(spends.flatMap(\.samples), range: range, now: now)
        let peak = buckets.map(\.total).max() ?? 0
        // Segments stack in the window's overall ranking, not each bucket's own, so a model
        // holds the same band across every bar instead of swapping places between them.
        let order = AgentUsage.byModel(spends, since: since).map(\.key)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AgentUsage.short(total.total)).font(Typography.title)
                Text("tokens").font(Typography.body).foregroundStyle(Theme.tx3)
                Spacer(minLength: 12)
                Picker("", selection: $range) {
                    ForEach(UsageRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            Text(
                "\(Int((total.cacheRate * 100).rounded()))% from cache · "
                    + "\(windowed.filter(\.running).count) running · in the \(range.caption)"
            )
            .font(Typography.body).foregroundStyle(Theme.tx3)
            if peak == 0 {
                Text("Nothing spent in the \(range.caption).")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
                    .frame(maxWidth: .infinity, minHeight: 108, alignment: .center)
            } else {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(buckets) { bar($0, peak: peak, order: order) }
                }
                .frame(height: 108)
                axis(buckets)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
        // A bar is coloured rectangles and nothing else, so a reader gets silence from it
        // unless it is told what it is worth. Same two facts the tooltip carries.
        .accessibilityElement()
        .accessibilityLabel("\(stamp(bucket.start)), \(AgentUsage.short(bucket.total))")
    }

    /// Three marks rather than one per bar: the range is the axis, and a label under every
    /// bucket would be unreadable at 12 buckets and absurd at 32.
    private func axis(_ buckets: [UsageBucket]) -> some View {
        HStack(spacing: 0) {
            ForEach(
                [buckets.first, buckets[buckets.count / 2], buckets.last].compactMap { $0 },
                id: \.id
            ) { bucket in
                Text(stamp(bucket.start)).font(Typography.monoCaption).foregroundStyle(Theme.tx4)
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

    /// One row per coding tool, the one closest to a limit first, so the answer to "can I
    /// keep going" is the top line. A row grows sideways by windows, the list down by tools,
    /// and neither ever needs a scroll of its own.
    private var limits: some View {
        let rows = quotas.sorted { tightest($0) > tightest($1) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Plan limits", trailing: "tightest first")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.provider) { index, quota in
                    if index > 0 { Divider().overlay(Theme.line) }
                    limitRow(quota)
                }
            }
            .cardSurface(padding: 6)
        }
    }

    /// A tool with nothing on disk sorts under every tool that reported, even one at 0%.
    private func tightest(_ quota: ProviderQuota) -> Double {
        quota.windows.map(\.percent).max() ?? -1
    }

    private func limitRow(_ quota: ProviderQuota) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 8) {
                Image(systemName: quota.provider.systemImage)
                    .font(.system(size: 11)).foregroundStyle(Theme.tx2).frame(width: 14)
                Text(quota.provider.displayName).font(Typography.headline).lineLimit(1)
                if let plan = quota.plan {
                    NotebookStyle.chip(plan.replacingOccurrences(of: "_", with: " "))
                }
            }
            .frame(width: 210, alignment: .leading)
            if quota.windows.isEmpty {
                Text("No limits reported.")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(quota.windows) { window($0) }
            }
            Text(quota.asOf.map { AgentUsage.ago($0) } ?? "—")
                .font(Typography.monoCaption).foregroundStyle(Theme.tx4)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .opacity(quota.windows.isEmpty ? 0.6 : 1)
    }

    private func window(_ window: PlanWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(Int(window.percent.rounded()))%")
                    .font(Typography.mono(.semibold))
                    .foregroundStyle(AgentUsage.tint(window.percent))
                Text(window.name).font(Typography.caption).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 8)
                if let until = AgentUsage.until(window.resetsAt) {
                    Text("resets \(until)").font(Typography.monoCaption).foregroundStyle(Theme.tx4)
                        .lineLimit(1)
                }
            }
            MeterBar(value: window.percent / 100, tint: AgentUsage.tint(window.percent), height: 5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Where it went

    /// The three ways the range's spend is cut. One panel with a switch rather than three
    /// panels side by side: the question is always "where did it go", only the cut changes.
    private enum Breakdown: String, CaseIterable, Identifiable {
        case project = "Project"
        case model = "Model"
        case agent = "Agent"
        var id: Self { self }
    }

    private var whereItWent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Where it went").font(Typography.headline)
                Spacer(minLength: 12)
                Picker("", selection: $breakdown) {
                    ForEach(Breakdown.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            if windowed.isEmpty {
                Text(
                    spends.isEmpty
                        ? "No agent has a transcript on disk yet. Assign work on the board and "
                            + "its agents show up here as they run."
                        : "Nothing spent in the \(range.caption)."
                )
                .font(Typography.body).foregroundStyle(Theme.tx3)
            } else {
                switch breakdown {
                case .project:
                    let rows = AgentUsage.group(windowed, since: since) { owners[$0.id] }
                    ForEach(rows, id: \.key) { row in
                        shareRow(
                            projects.first { $0.id == row.key }?.name ?? "Elsewhere", row.tally,
                            peak: rows.first?.tally.total ?? 0, tint: Theme.accent)
                    }
                case .model:
                    let rows = AgentUsage.byModel(spends, since: since)
                    ForEach(rows, id: \.key) { row in
                        shareRow(
                            AgentUsage.modelName(row.key), row.tally,
                            peak: rows.first?.tally.total ?? 0, tint: tint(row.key))
                    }
                case .agent:
                    // Runs rather than sums: each row opens the transcript it counts.
                    VStack(spacing: 0) { ForEach(windowed) { agentRow($0) } }
                        .padding(.horizontal, -8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Ranked against the biggest row, so the top one always fills its track — the
    /// comparison is between rows, not against an absolute nobody knows.
    private func shareRow(_ name: String, _ tally: TokenTally, peak: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(name).font(Typography.body).foregroundStyle(Theme.tx).lineLimit(1)
                Text("\(share(tally))%").font(Typography.mono).foregroundStyle(Theme.tx4)
                Spacer(minLength: 8)
                Text(AgentUsage.short(tally.total)).font(Typography.mono(.semibold)).foregroundStyle(Theme.tx2)
            }
            MeterBar(value: peak == 0 ? 0 : Double(tally.total) / Double(peak), tint: tint)
        }
    }

    private func agentRow(_ spend: AgentSpend) -> some View {
        Button {
            if let route = spend.route, let owner = owners[spend.id] { open(owner, route) }
        } label: {
            HStack(spacing: 10) {
                RoleTile(role: spend.role, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(person(spend)).font(Typography.body).foregroundStyle(Theme.tx).lineLimit(1)
                        if spend.running { StateDot(live: true) }
                    }
                    HStack(spacing: 6) {
                        // The run's own label, when it says more than the name above does —
                        // which dispatch of a subagent this row is.
                        if spend.name != person(spend) {
                            Text(spend.name).font(Typography.monoCaption).foregroundStyle(Theme.tx4)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        if let project = owner(of: spend) {
                            Text(project.name).font(Typography.monoCaption).foregroundStyle(Theme.tx3).lineLimit(1)
                        }
                        if let model = spend.topModel(since: since) {
                            Text(AgentUsage.modelName(model))
                                .font(Typography.monoCaption).foregroundStyle(tint(model))
                        }
                        Text(spend.provider.displayName).font(Typography.monoCaption).foregroundStyle(Theme.tx4)
                    }
                }
                Spacer(minLength: 12)
                MeterBar(value: fraction(spend.tally(since: since)), tint: RoleTile.color(of: spend.role))
                    .frame(width: 90)
                Text(AgentUsage.short(spend.tally(since: since).total))
                    .font(Typography.code(.semibold)).foregroundStyle(Theme.tx)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(spend.route == nil)
    }

    /// Whose spend a run is. A team member's subagent is that member, by the skill it ran;
    /// anything else is itself.
    private func person(_ spend: AgentSpend) -> String {
        Team.running(spend.role, in: owner(of: spend)?.team ?? [])?.member.name ?? spend.name
    }

    private func owner(of spend: AgentSpend) -> Project? {
        owners[spend.id].flatMap { id in projects.first { $0.id == id } }
    }

    // MARK: - Shared

    /// Every bar on this screen is a share of the spend on it, so the widest one is
    /// always full — the comparison is between agents, not against an absolute nobody knows.
    private func fraction(_ tally: TokenTally) -> Double {
        let top = windowed.first?.tally(since: since).total ?? 0
        return top == 0 ? 0 : Double(tally.total) / Double(top)
    }

    private func share(_ tally: TokenTally) -> Int {
        total.total == 0 ? 0 : Int((Double(tally.total) / Double(total.total) * 100).rounded())
    }
}
