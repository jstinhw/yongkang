import Foundation
import YongkangCore

// Where the window was when it last closed. `@AppStorage("openProjects")` has already
// reopened the folders by the time any of this runs; what is left is the address inside
// them, which `RootView` keeps in `@SceneStorage`.

extension AppModel {
    /// Every open project's agent sessions, as `@AppStorage("openSessions")` keeps them.
    var storedSessions: String {
        OpenSessions.encode(
            Dictionary(
                projects.map { ($0.directory.path, OpenSessions.stored($0.sessions)) },
                uniquingKeysWith: { first, _ in first }))
    }

    /// Starts the agents the last run had open, each on its own conversation where its CLI
    /// kept one, so a quit or a crash loses neither the agent nor the tasks it holds — the ids
    /// that keep its finished, unapproved work in Review. A project no longer open is skipped.
    /// A session whose chain finished while the app was closed does not come back: it has
    /// nothing left to do, and `endSpentSessions` would close it a beat later anyway — after
    /// starting a CLI and putting a row in the sidebar for the user to watch vanish. Its
    /// reports are in `runs/`, so work it finished but you have not approved is still in
    /// Review, and sending that task back starts a fresh agent with your comments.
    ///
    /// The notebook is read first for that reason alone: nothing else here needs it, and the
    /// read that follows a moment later answers from what this one already found.
    func resumeSessions(_ stored: String) async {
        let stored = OpenSessions.decode(stored)
        for project in projects {
            await project.reloadNotebook(frontmatter: true, records: false)
            let notebook = project.value
            for session in stored[project.directory.path] ?? [] where !notebook.isSpent(session.taskIDs) {
                let line = await OpenSessions.line(resuming: session, in: project.directory)
                project.addSession(
                    id: session.id, title: session.title, icon: session.icon, line: line, agent: session.agent,
                    taskIDs: session.taskIDs, reading: session.reading.map { URL(fileURLWithPath: $0) })
            }
            // A request Product finished but nobody approved is on disk, not in the stored sessions.
            if let product = project.sessions.last(where: \.isProduct) {
                await project.refreshRepo(countingLines: false)
                project.resumeRequest(of: product)
            }
        }
    }

    /// Enters the project the window was inside and puts it back on the page it had open.
    /// Does nothing if that folder is no longer open — the window then stays on the fleet
    /// screen, which is where a first launch starts anyway.
    func restore(entered path: String, section: ConsoleSection, route: Route?) {
        // Usage belongs to no project, so it is the one page that comes back with none entered.
        if route == .usage { return openUsage() }
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
        case .board, .agents, .memory(nil), .skills:
            return true
        // Every project's, not this one's: see `restore(entered:section:route:)`.
        case .usage: return false
        case .project(let id): return cards.contains { $0.id == id && $0.kind == .project }
        case .task(let id): return cards.contains { $0.id == id && $0.kind == .task }
        case .page(let id), .memory(let id?): return cards.contains { $0.id == id }
        case .entry(let id): return NotebookLoader.find(id, in: project.snapshot.entries) != nil
        case .block(let id): return project.snapshot.blocks.contains { $0.id == id }
        case .member(let name): return project.snapshot.team.contains { $0.name == name }
        // A session comes back when `resumeSessions` started it again; its subagents are
        // read off disk later, so one of theirs is stale on a relaunch.
        case .session(let id, _): return project.sessions.contains { $0.id == id }
        case .subagent: return false
        // These name what git and service detection say, and neither has been read when the
        // window restores. The next finished task re-opens its review once that read lands.
        case .review, .reviewTask, .preview: return false
        }
    }
}
