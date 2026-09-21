import Foundation
import YongkangCore

extension ProjectModel {
    /// The `.notebook/projects/<id>` the selection sits in — memory has to land in one.
    func notebookProject(for selection: Route?) -> String? {
        if case .project(let scope) = selection { return scope }
        if case .task(let id) = selection,
            let owner = snapshot.cards.first(where: { $0.id == id })?.project
        {
            return owner
        }
        guard case .entry(let path) = selection,
            path.hasPrefix(NotebookEntry.id(for: directory)),
            let marker = path.range(of: "/\(NotebookFormat.folderName)/projects/")
        else { return nil }
        return path[marker.upperBound...].split(separator: "/").first.map(String.init)
    }

    /// A new entry titled `title`, filed under whatever `selection` sits in, and its page on
    /// the board. Its card only exists after the next reload, so reload before going there.
    func add(_ kind: EntryKind, title: String, selection: Route?) throws -> Destination {
        let file = try NotebookFormat.create(
            kind, title: title, in: notebookRoot,
            project: notebookProject(for: selection),
            roadmap: notebookRoadmap(for: selection),
            subject: selection?.cardID ?? notebookProject(for: selection))
        let id =
            kind == .project
            ? file.deletingLastPathComponent().lastPathComponent
            : file.deletingPathExtension().lastPathComponent
        switch kind {
        case .project: return Destination(section: .board, route: .project(id))
        case .task: return Destination(section: .board, route: .task(id))
        // Memory is read under Agents now, beside the agents who write it.
        case .memory: return Destination(section: .agents, route: .memory(id))
        case .roadmap, .run: return Destination(section: .board, route: .page(id))
        }
    }

    /// Removing a notebook entry. A project takes its tasks with it — a task filed under
    /// an id that no longer exists shows up nowhere and would never be worked.
    ///
    /// `cards` is the board the user confirmed against, not the snapshot now: the poll can
    /// change it while they are asked, and what goes must be what they were told goes.
    /// Returns the board when the page on screen went too, and nil when it is still there.
    func remove(
        _ card: NotebookCard, from cards: [NotebookCard], selection: Route?, trash: Bool = true
    ) throws -> Route? {
        try NotebookFormat.remove(card, in: cards, trash: trash)
        // Anything on screen that was inside what just went to the Trash has no page left.
        let gone = Set(NotebookFormat.owned(by: card, in: cards).map(\.path))
        guard let shown = selection?.card(in: cards),
            gone.contains(where: { shown.url.path == $0 || shown.url.path.hasPrefix($0 + "/") })
        else { return nil }
        return .board
    }

    private func notebookRoadmap(for selection: Route?) -> String? {
        if case .page(let id) = selection,
            snapshot.cards.contains(where: { $0.id == id && $0.kind == .roadmap })
        {
            return id
        }
        let roadmaps = snapshot.cards.filter { $0.kind == .roadmap }
        return roadmaps.count == 1 ? roadmaps[0].id : nil
    }
}
