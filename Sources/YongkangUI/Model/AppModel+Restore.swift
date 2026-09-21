import Foundation
import YongkangCore

// Where the window was when it last closed. `@AppStorage("openProjects")` has already
// reopened the folders by the time any of this runs; what is left is the address inside
// them, which `RootView` keeps in `@SceneStorage`.

extension AppModel {
    /// Enters the project the window was inside and puts it back on the page it had open.
    /// Does nothing if that folder is no longer open — the window then stays on the fleet
    /// screen, which is where a first launch starts anyway.
    func restore(entered path: String, section: ConsoleSection, route: Route?) {
        guard !path.isEmpty, let project = projects.first(where: { $0.directory.path == path }) else { return }
        enter(project)
        self.section = section
        // A stored route names something an agent may have deleted while the app was closed,
        // and a session route never survives at all. Rather than drawing "Nothing selected",
        // a route that no longer points anywhere is dropped and the section opens on its own
        // default — the session still on assigned work, or the board.
        selection = route.flatMap { restorable($0, in: project) ? $0 : nil }
        if selection == nil { openSectionDefault() }
    }

    /// Whether `route` still names something `project` has, as its notebook reads now.
    func restorable(_ route: Route, in project: ProjectModel) -> Bool {
        let cards = project.snapshot.cards
        switch route {
        // Screens rather than objects: there is nothing for them to have lost.
        case .board, .usage, .agents, .memory(nil):
            return true
        case .project(let id): return cards.contains { $0.id == id && $0.kind == .project }
        case .task(let id): return cards.contains { $0.id == id && $0.kind == .task }
        case .page(let id), .memory(let id?): return cards.contains { $0.id == id }
        case .entry(let id): return NotebookLoader.find(id, in: project.snapshot.entries) != nil
        case .block(let id): return project.snapshot.blocks.contains { $0.id == id }
        case .member(let name): return project.snapshot.team.contains { $0.name == name }
        // The agents died with the app, so a session route is stale by definition on a
        // relaunch. Agents opens on whatever is running, which is nothing yet.
        case .session, .subagent: return false
        // These name what git and service detection say, and neither has been read when the
        // window restores. The next finished task re-opens its review once that read lands.
        case .review, .reviewTask, .preview: return false
        }
    }
}
