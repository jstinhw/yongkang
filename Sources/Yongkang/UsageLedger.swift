import Foundation

/// What every agent this project has run has spent, kept in the notebook beside the work
/// it paid for.
///
/// The transcripts outlive the app, but the app's link to them does not: sessions are not
/// restored on relaunch, so on the next launch there is nothing left pointing at the files
/// that hold the numbers. This is that pointer, resolved — the totals themselves, written
/// down while they can still be read.
///
/// Rolled up by the hour rather than kept per turn. A turn-by-turn log would grow without
/// bound in a folder the user commits, and every window past the first buckets an hour or
/// wider anyway; only the live session, still read from its own transcript, needs finer.
package enum UsageLedger {

    private struct Ledger: Codable {
        var version = 1
        var agents: [Record] = []
    }

    private struct Record: Codable {
        var id: String
        var name: String
        var role: String
        var provider: String
        var hours: [Hour]
    }

    private struct Hour: Codable {
        var at: Date
        var model: String
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheWrite: Int

        var tally: TokenTally {
            TokenTally(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite)
        }
    }

    package static func url(root: URL) -> URL { root.appendingPathComponent("usage.json") }

    /// Folds what the transcripts currently say into the ledger and writes it back.
    /// Returns whether anything was actually written — this is called from the app's
    /// two-second poll, and an unchanged ledger is left alone.
    @discardableResult
    package static func record(_ spends: [AgentSpend], root: URL) -> Bool {
        guard !spends.isEmpty else { return false }
        var byID = Dictionary(
            read(root: root).agents.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        for spend in spends where !spend.samples.isEmpty {
            var record =
                byID[spend.id]
                ?? Record(
                    id: spend.id, name: spend.name, role: spend.role,
                    provider: spend.provider.rawValue, hours: [])
            // A lead can be renamed and a subagent's label rewritten between runs; the
            // hours are the record, the name is only how it is shown.
            record.name = spend.name
            record.role = spend.role
            record.hours = merge(record.hours, with: rollup(spend.samples))
            byID[spend.id] = record
        }
        var ledger = Ledger()
        ledger.agents = byID.values.sorted { $0.id < $1.id }
        return write(ledger, root: root)
    }

    /// The agents the ledger remembers, shaped as spends so the usage screen can show them
    /// beside the live ones. Their samples are hour marks rather than turns, which is all
    /// the file keeps — and they carry no tag, because the session that produced them is
    /// gone and there is nothing left for a click to open.
    package static func load(root: URL) -> [AgentSpend] {
        read(root: root).agents.map { record in
            AgentSpend(
                id: record.id, tag: "", name: record.name, role: record.role,
                provider: AgentKind(rawValue: record.provider) ?? .claude, running: false,
                samples: record.hours
                    .map { UsageSample(at: $0.at, model: $0.model, tally: $0.tally) }
                    .sorted { $0.at < $1.at })
        }
    }

    /// Usage only ever accumulates, so for the same agent, hour and model the larger of
    /// two readings is the right one. That makes a re-read safe however it lands against
    /// what is already written — including a transcript the CLI has since truncated or
    /// rotated, which a straight replace would silently erase the history of.
    private static func merge(_ existing: [Hour], with fresh: [Hour]) -> [Hour] {
        var byKey: [String: Hour] = [:]
        for hour in existing + fresh {
            let key = "\(Int(hour.at.timeIntervalSince1970))|\(hour.model)"
            if let held = byKey[key], held.tally.total >= hour.tally.total { continue }
            byKey[key] = hour
        }
        return byKey.values.sorted { ($0.at, $0.model) < ($1.at, $1.model) }
    }

    private static func rollup(_ samples: [UsageSample]) -> [Hour] {
        var byKey: [String: Hour] = [:]
        for sample in samples {
            let at = Date(timeIntervalSince1970: (sample.at.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
            let key = "\(Int(at.timeIntervalSince1970))|\(sample.model)"
            var hour =
                byKey[key]
                ?? Hour(
                    at: at, model: sample.model,
                    input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
            hour.input += sample.tally.input
            hour.output += sample.tally.output
            hour.cacheRead += sample.tally.cacheRead
            hour.cacheWrite += sample.tally.cacheWrite
            byKey[key] = hour
        }
        return Array(byKey.values)
    }

    private static func read(root: URL) -> Ledger {
        guard let data = try? Data(contentsOf: url(root: root)) else { return Ledger() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Ledger.self, from: data)) ?? Ledger()
    }

    private static func write(_ ledger: Ledger, root: URL) -> Bool {
        // A project with no notebook is left untouched, the same as everywhere else: the
        // app does not create a folder in someone's repo to file its own bookkeeping.
        guard FileManager.default.fileExists(atPath: root.path) else { return false }
        let encoder = JSONEncoder()
        // Sorted and pretty because this file sits in a notebook people commit, and a
        // ledger that reshuffles itself every write is unreadable in a diff.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(ledger),
            (try? Data(contentsOf: url(root: root))) != data
        else { return false }
        try? data.write(to: url(root: root), options: .atomic)
        return true
    }
}
