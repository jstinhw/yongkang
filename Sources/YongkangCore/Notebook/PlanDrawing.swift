import Foundation

/// A plan laid out for its page: where every card sits, where every arrow starts and ends, and
/// a band behind each project's tasks. Worked out here, where it is tested like the rest of
/// Core, so the page's script only paints it and pans and zooms.
///
/// Columns are build order: a task sits one column right of the last thing it waits on. Each
/// project's tasks keep to a band of rows of their own, ordered so a task sits level with
/// what it waits on. What the plan builds on stays out of the bands: one column left of the
/// first task that needs it, so its arrow is short, and level with that task unless a band
/// is in the way, in which case it goes below them.
package struct PlanDrawing: Encodable, Equatable, Sendable {
    package enum Kind: String, Encodable, Sendable {
        /// A task the plan builds.
        case task
        /// Something the plan builds on that already exists.
        case built
        /// Something the plan builds on that does not exist yet: another board's task.
        case pending
    }

    package struct Node: Encodable, Equatable, Sendable {
        package let id: String
        package let title: String
        package let detail: String
        /// Where something outside the plan comes from, under its card. Empty on a task.
        package let caption: String
        package let kind: Kind
        package let design: Bool
        /// One of the moments the plan waits on the user belongs to it.
        package let you: Bool
        /// Everything it waits on exists, so it can start at once.
        package let ready: Bool
        package let x: Int
        package let y: Int
    }

    package struct Edge: Encodable, Equatable, Sendable {
        package let from: String
        package let to: String
        package let x1: Int
        package let y1: Int
        package let x2: Int
        package let y2: Int
        /// It leaves something that does not exist yet.
        package let dashed: Bool
    }

    package struct Band: Encodable, Equatable, Sendable {
        package let title: String
        package let x: Int
        package let y: Int
        package let width: Int
        package let height: Int
    }

    package let title: String
    package let outcomes: [String]
    package let needsYou: [Plan.Ask]
    package let nodes: [Node]
    package let edges: [Edge]
    package let bands: [Band]
    package let width: Int
    package let height: Int
    package let nodeWidth = Metrics.nodeWidth
    package let nodeHeight = Metrics.nodeHeight

    /// Sizes in CSS pixels at 100%. A card holds a five-word title on one line.
    enum Metrics {
        static let margin = 40
        static let nodeWidth = 224
        static let nodeHeight = 64
        static let gapX = 64
        static let gapY = 36
        /// Room above a band's first row for its project's name, and below its last.
        static let bandHead = 32
        static let bandFoot = 16
        static let bandGap = 24
        static let bandInset = 16
        static let caption = 22
        static var pitch: Int { nodeHeight + gapY }
    }

    package init(_ plan: Plan) {
        var seen: Set<String> = []
        let tasks = plan.tasks.filter { seen.insert($0.id).inserted }
        let outside = (plan.outside ?? []).filter { seen.insert($0.id).inserted }
        // A dependency on an id the plan does not name has nothing to point from.
        let depends = Dictionary(
            uniqueKeysWithValues: tasks.map { task in
                (task.id, Array(Set(task.dependsOn ?? []).intersection(seen).subtracting([task.id])).sorted())
            })
        let grid = PlanGrid(tasks: tasks, outside: outside, depends: depends)
        let you = Set((plan.needsYou ?? []).map(\.task))
        let built = Set(outside.filter { $0.done != false }.map(\.id))

        let taskNodes = tasks.map { task in
            Node(
                id: task.id, title: task.title, detail: task.detail ?? "", caption: "", kind: .task,
                design: task.design ?? false, you: you.contains(task.id),
                ready: depends[task.id, default: []].allSatisfy(built.contains),
                x: grid.x(task.id), y: grid.y(task.id))
        }
        let outsideNodes = outside.map { item in
            Node(
                id: item.id, title: item.title, detail: "", caption: item.place ?? "",
                kind: built.contains(item.id) ? .built : .pending, design: false, you: false, ready: false,
                x: grid.x(item.id), y: grid.y(item.id))
        }
        let nodes = taskNodes + outsideNodes
        let bands = grid.bands()

        title = plan.title
        outcomes = plan.outcomes ?? []
        needsYou = plan.needsYou ?? []
        self.nodes = nodes
        edges = Self.edges(between: nodes, depends: depends, order: tasks.map(\.id))
        self.bands = bands
        let right = nodes.map { $0.x + Metrics.nodeWidth } + bands.map { $0.x + $0.width }
        let bottom =
            nodes.map { $0.y + Metrics.nodeHeight + ($0.caption.isEmpty ? 0 : Metrics.caption) }
            + bands.map { $0.y + $0.height }
        width = (right.max() ?? 0) + Metrics.margin
        height = (bottom.max() ?? 0) + Metrics.margin
    }

    /// One arrow per dependency. Several arrows into one card arrive spread down its edge in
    /// the order their sources sit, and several out of one leave the same way, so none cross
    /// at the card.
    private static func edges(between nodes: [Node], depends: [String: [String]], order: [String]) -> [Edge] {
        let at = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let links = order.flatMap { to in depends[to, default: []].map { (from: $0, to: to) } }
        let above = { (a: Node, b: Node) in (a.y, a.x) < (b.y, b.x) }
        let incoming = Dictionary(grouping: links, by: \.to).mapValues {
            $0.map(\.from).sorted { above(at[$0]!, at[$1]!) }
        }
        let outgoing = Dictionary(grouping: links, by: \.from).mapValues {
            $0.map(\.to).sorted { above(at[$0]!, at[$1]!) }
        }
        func port(_ id: String, among ids: [String], on node: Node) -> Int {
            node.y + Metrics.nodeHeight * (ids.firstIndex(of: id)! + 1) / (ids.count + 1)
        }
        return links.map { link in
            let from = at[link.from]!
            let to = at[link.to]!
            return Edge(
                from: link.from, to: link.to,
                x1: from.x + Metrics.nodeWidth, y1: port(link.to, among: outgoing[link.from]!, on: from),
                x2: to.x, y2: port(link.from, among: incoming[link.to]!, on: to),
                dashed: from.kind == .pending)
        }
    }
}

/// Where each card goes in columns and rows, before any pixels.
private struct PlanGrid {
    typealias Metrics = PlanDrawing.Metrics

    struct Lane {
        let title: String
        let rows: Range<Int>
        let columns: ClosedRange<Int>
    }

    private(set) var column: [String: Int] = [:]
    private(set) var row: [String: Int] = [:]
    private(set) var lanes: [Lane] = []
    private var taken: [Int: Set<Int>] = [:]

    init(tasks: [Plan.Task], outside: [Plan.Outside], depends: [String: [String]]) {
        column = Self.columns(of: tasks, depends: depends)
        let dependents = Dictionary(
            grouping: tasks.flatMap { task in depends[task.id, default: []].map { ($0, task.id) } }, by: \.0
        )
        .mapValues { $0.map(\.1) }
        for item in outside {
            column[item.id] = max(0, (dependents[item.id, default: []].compactMap { column[$0] }.min() ?? 1) - 1)
        }
        placeTasks(tasks, depends: depends)
        let lanes = self.lanes
        for item in outside {
            let col = column[item.id]!
            let desired = center(of: dependents[item.id, default: []]) ?? lanes.last?.rows.upperBound ?? 0
            settle(item.id, column: col, near: desired) { row in
                !lanes.contains { $0.rows.contains(row) && $0.columns.contains(col) }
            }
        }
    }

    /// Longest path from what has no dependencies. Something outside the plan counts as
    /// column 0 here and is pulled right afterwards. A cycle is cut where it closes rather
    /// than followed round.
    private static func columns(of tasks: [Plan.Task], depends: [String: [String]]) -> [String: Int] {
        var memo: [String: Int] = [:]
        var visiting: Set<String> = []
        func rank(_ id: String) -> Int {
            if let known = memo[id] { return known }
            guard let deps = depends[id], visiting.insert(id).inserted else { return 0 }
            let value = deps.map { rank($0) + 1 }.max() ?? 0
            visiting.remove(id)
            memo[id] = value
            return value
        }
        for task in tasks { _ = rank(task.id) }
        return memo
    }

    /// A band per project, in the order the plan first names them, as tall as its fullest
    /// column. Column by column, each task goes to the free row in its band nearest the rows of
    /// what it waits on, so a chain runs straight.
    private mutating func placeTasks(_ tasks: [Plan.Task], depends: [String: [String]]) {
        var projects: [String] = []
        for task in tasks where !projects.contains(task.project ?? "") { projects.append(task.project ?? "") }
        var next = 0
        for project in projects {
            let mine = tasks.filter { ($0.project ?? "") == project }
            let cols = mine.map { column[$0.id]! }
            let height = Dictionary(grouping: cols, by: { $0 }).values.map(\.count).max()!
            lanes.append(Lane(title: project, rows: next..<next + height, columns: cols.min()!...cols.max()!))
            next += height
        }
        for col in 0...(column.values.max() ?? 0) {
            for (lane, project) in zip(lanes, projects) {
                let here = tasks.filter { ($0.project ?? "") == project && column[$0.id] == col }
                    .enumerated()
                    .map {
                        (offset: $0.offset, id: $0.element.id, center: center(of: depends[$0.element.id, default: []]))
                    }
                    .sorted { ($0.center ?? .max, $0.offset) < ($1.center ?? .max, $1.offset) }
                for task in here {
                    let desired = min(
                        max(task.center ?? lane.rows.lowerBound, lane.rows.lowerBound), lane.rows.upperBound - 1)
                    settle(task.id, column: col, near: desired) { lane.rows.contains($0) }
                }
            }
        }
    }

    /// The row level with the given cards, among those already placed.
    private func center(of ids: [String]) -> Int? {
        let rows = ids.compactMap { row[$0] }
        guard !rows.isEmpty else { return nil }
        return Int((Double(rows.reduce(0, +)) / Double(rows.count)).rounded())
    }

    /// The free row nearest `desired` that `allowed` takes, looking below before above. There
    /// always is one: a band has a row for each of its cards in a column, and below the bands
    /// every row is allowed.
    private mutating func settle(_ id: String, column col: Int, near desired: Int, allowed: (Int) -> Bool) {
        let used = taken[col, default: []]
        let found = (0...).lazy.flatMap { [desired + $0, desired - $0] }
            .first { $0 >= 0 && allowed($0) && !used.contains($0) }!
        row[id] = found
        taken[col, default: []].insert(found)
    }

    func x(_ id: String) -> Int { Metrics.margin + column[id]! * (Metrics.nodeWidth + Metrics.gapX) }

    func y(_ id: String) -> Int {
        let r = row[id]!
        let tops = laneTops()
        if let index = lanes.firstIndex(where: { $0.rows.contains(r) }) {
            return tops[index] + Metrics.bandHead + (r - lanes[index].rows.lowerBound) * Metrics.pitch
        }
        return tops[lanes.count] + (r - (lanes.last?.rows.upperBound ?? 0)) * Metrics.pitch
    }

    /// Where each band starts, and then where the rows below them all start.
    private func laneTops() -> [Int] {
        lanes.reduce(into: [Metrics.margin]) { tops, lane in
            tops.append(tops.last! + bandHeight(lane) + Metrics.bandGap)
        }
    }

    private func bandHeight(_ lane: Lane) -> Int {
        Metrics.bandHead + lane.rows.count * Metrics.pitch - Metrics.gapY + Metrics.bandFoot
    }

    func bands() -> [PlanDrawing.Band] {
        zip(lanes, laneTops()).map { lane, top in
            let left = Metrics.margin + lane.columns.lowerBound * (Metrics.nodeWidth + Metrics.gapX)
            return PlanDrawing.Band(
                title: lane.title, x: left - Metrics.bandInset, y: top,
                width: lane.columns.count * (Metrics.nodeWidth + Metrics.gapX) - Metrics.gapX + 2 * Metrics.bandInset,
                height: bandHeight(lane))
        }
    }
}
