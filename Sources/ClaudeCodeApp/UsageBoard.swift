import SwiftUI

/// What the agents are costing, in one screen: how close each coding tool is to its plan
/// limit, which models the spend went to, which role spent it, and which individual agent.
/// Every number is read off the same transcripts the rest of the console watches, so this
/// screen keeps no state of its own to drift out of date.
struct UsageBoard: View {
    let project: Project
    let open: (String) -> Void

    /// Loaded on a change rather than per render: parsing transcripts inside `body` at
    /// 60fps would be the most expensive thing in the app.
    @State private var spends: [AgentSpend] = []
    @State private var quotas: [ProviderQuota] = []

    private var total: TokenTally { spends.map(\.tally).reduce(TokenTally(), +) }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 20) {
                    limits
                    byModel
                    byAgent
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 20) {
                    totals
                    byRole
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
        project.sessions.map { session in
            session.id.uuidString + session.subagents.map { $0.id + "\($0.running)" }.joined()
        }.joined() + "\(project.sessions.count)"
    }

    private func load() {
        spends = AgentUsage.spends(in: project)
        quotas = [AgentUsage.claudeQuota(), AgentUsage.codexQuota()].compactMap { $0 }
    }

    // MARK: - Plan limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Plan limits", trailing: "read from each CLI's own cache")
            if quotas.isEmpty {
                note("No plan limits on disk yet. Both CLIs write these as they work — run "
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
        let rows = AgentUsage.byModel(spends)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("By model", trailing: rows.isEmpty ? nil : "\(rows.count)")
            if rows.isEmpty {
                note("Nothing spent yet.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // One bar for the whole project, split by model — the share each model
                    // took is the question, and separate bars would not answer it.
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(rows, id: \.key) { row in
                                Capsule().fill(AgentUsage.modelTint(row.key))
                                    .frame(width: max(2, geo.size.width
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
            Circle().fill(AgentUsage.modelTint(model)).frame(width: 7, height: 7)
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
            ForEach([("out", tally.output), ("in", tally.input),
                     ("cache", tally.cacheRead + tally.cacheWrite)], id: \.0) { label, value in
                Text("\(label) \(AgentUsage.short(value))")
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
            }
        }
    }

    // MARK: - By agent

    private var byAgent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("By agent", trailing: spends.isEmpty ? nil : "\(spends.count)")
            if spends.isEmpty {
                note("No agent has a transcript on disk yet. Assign work on the board and "
                     + "the lead's specialists show up here as they run.")
            } else {
                VStack(spacing: 0) {
                    ForEach(spends) { agentRow($0) }
                }
                .cardSurface(padding: 6)
            }
        }
    }

    private func agentRow(_ spend: AgentSpend) -> some View {
        Button { open(spend.tag) } label: {
            HStack(spacing: 10) {
                RoleTile(role: spend.role, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(spend.name).font(Typo.text(12.5)).foregroundStyle(Theme.tx).lineLimit(1)
                        if spend.running { StateDot(live: true) }
                    }
                    HStack(spacing: 6) {
                        if let model = spend.topModel {
                            Text(AgentUsage.modelName(model))
                                .font(Typo.mono(9.5)).foregroundStyle(AgentUsage.modelTint(model))
                        }
                        Text(spend.provider.displayName).font(Typo.mono(9.5)).foregroundStyle(Theme.tx4)
                    }
                }
                Spacer(minLength: 12)
                MeterBar(value: fraction(spend.tally), tint: RoleTile.color(of: spend.role))
                    .frame(width: 90)
                Text(AgentUsage.short(spend.tally.total))
                    .font(Typo.mono(11.5, .semibold)).foregroundStyle(Theme.tx)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.clear))
    }

    // MARK: - Totals and roles

    private var totals: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("This project")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AgentUsage.short(total.total)).font(Typo.display(26))
                    Text("tokens").font(Typo.text(12)).foregroundStyle(Theme.tx3)
                }
                ForEach([("Output", total.output), ("Input", total.input),
                         ("Cache write", total.cacheWrite), ("Cache read", total.cacheRead)],
                        id: \.0) { label, value in
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
                    Text("\(spends.filter(\.running).count) running · \(spends.count) total")
                        .font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private var byRole: some View {
        let rows = AgentUsage.group(spends, by: \.role)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("By role", trailing: "product · lead · specialists")
            if rows.isEmpty {
                note("Nothing spent yet.")
            } else {
                VStack(spacing: 11) {
                    ForEach(rows, id: \.key) { row in
                        let count = spends.filter { $0.role == row.key }.count
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 9) {
                                RoleTile(role: row.key, size: 20)
                                Text(row.key).font(Typo.text(12)).foregroundStyle(Theme.tx).lineLimit(1)
                                Text("\(count)").font(Typo.mono(10)).foregroundStyle(Theme.tx4)
                                Spacer(minLength: 8)
                                Text(AgentUsage.short(row.tally.total))
                                    .font(Typo.mono(11, .semibold)).foregroundStyle(Theme.tx2)
                            }
                            MeterBar(value: fraction(row.tally), tint: RoleTile.color(of: row.key))
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    // MARK: - Shared

    /// Every bar on this screen is a share of the project's own spend, so the widest one is
    /// always full — the comparison is between agents, not against an absolute nobody knows.
    private func fraction(_ tally: TokenTally) -> Double {
        let top = spends.first?.tally.total ?? 0
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
