import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // MARK: - Assigning

    /// Where a workflow said to go. `input` only ever goes to the session `route` opens.
    func go(to destination: Destination?) {
        guard let destination else { return }
        model.section = destination.section
        if let route = destination.route { model.selection = route }
        if let input = destination.input, case .session(let id, _)? = destination.route {
            model.pendingInput[id] = input
        }
    }

    func assign(_ tasks: [NotebookCard], in project: ProjectModel) {
        guard let destination = project.assign(tasks, agent: agent) else {
            guard !tasks.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "Nothing to assign"
            alert.informativeText =
                "Every task here is already done, or already has an Engineering "
                + "Lead on it — wait for that session to finish, or close it, before assigning again."
            alert.runModal()
            return
        }
        go(to: destination)
    }

    // MARK: - Projects

    func openProject() {
        guard
            let path = pickDirectory(
                message: "Agents run in this folder and its notebook lives in \(NotebookFormat.folderName)/."
            )
        else { return }
        let directory = URL(fileURLWithPath: path)
        if let existing = model.project(at: directory) {
            model.enter(existing)
            return
        }
        let project = model.open(directory)
        persist()
        model.enter(project)
    }

    /// Where a described project lands when its prompt names nowhere: beside the ones
    /// already open, since that is where this person keeps projects, and `~/Projects` on
    /// a first run. Created on the way, so nothing has to be picked in a panel first.
    var projectsParent: URL {
        model.projects.last.map { $0.directory.deletingLastPathComponent() }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects")
    }

    /// A project described rather than opened: the folder is new and empty, so the prompt
    /// that named it goes straight to the session that writes its notebook — the intake
    /// screen has nothing left to ask.
    func createProject(at directory: URL, prompt: String) {
        creatingProject = false
        if let existing = model.project(at: directory) {
            model.enter(existing)
            return
        }
        let project = model.open(directory)
        persist()
        model.enter(project)
        guard let started = model.entered, !started.hasNotebook else { return }
        model.section = .agents
        addSession(
            agent, to: started,
            prompt: NotebookFormat.onboardingPrompt(description: prompt),
            title: "Notebook Setup")
    }

    func close(_ project: ProjectModel) {
        model.close(project)
        persist()
    }

    // MARK: - Review

    /// The failure is shown under the button rather than in an alert, so it comes back as text.
    func approve(_ task: SummaryTask, message: String, in project: ProjectModel) -> String? {
        do {
            model.selection = try project.approve(task, message: message)
            return nil
        } catch {
            return error.reason
        }
    }

    func commit(_ message: String, in project: ProjectModel) -> String? {
        do {
            model.selection = try project.commit(message)
            return nil
        } catch {
            return error.reason
        }
    }

    // MARK: - Sessions

    func addSession(
        _ agent: AgentKind, id: UUID = UUID(), to project: ProjectModel,
        prompt: String? = nil, title: String? = nil, taskIDs: [String] = []
    ) {
        model.selection = project.addSession(agent, id: id, prompt: prompt, title: title, taskIDs: taskIDs)
    }

    /// Every service in a project's repos, started at once — the board's "run the whole
    /// project" action.
    func runServices(_ card: NotebookCard, in project: ProjectModel) {
        runServices(Service.plan(for: card, in: project.directory), in: project)
    }

    func runServices(
        _ steps: [(repo: String, directory: URL, services: [Service.Runnable])],
        in project: ProjectModel
    ) {
        let run = project.runServices(steps)
        go(to: run.destination)
        guard !run.unstarted.isEmpty else { return }
        let alert = NSAlert()
        // No route means no service was started or shown: none of them had a command.
        alert.messageText = run.destination.route == nil ? "Nothing to run yet" : "Some services did not start"
        alert.informativeText = """
            No start command found in: \(run.unstarted.joined(separator: ", ")).

            A service starts if it has a compose file, an npm dev/start script, Cargo.toml, \
            go.mod, or a Makefile dev target. Add `repos: [path, ...]` to the project's \
            frontmatter to point at the folders that do, or split a repo that holds more than \
            one app into `apps/` or `services/` subfolders so each is found on its own.
            """
        alert.runModal()
    }

    // MARK: - Notebook entries

    /// The `.notebook/projects/<id>` the selection sits in — memory has to land in one.
    func notebookProject(in project: ProjectModel) -> String? {
        if case .project(let scope) = model.selection { return scope }
        if case .task(let id) = model.selection,
            let owner = project.snapshot.cards.first(where: { $0.id == id })?.project
        {
            return owner
        }
        guard case .entry(let path) = model.selection,
            path.hasPrefix(NotebookEntry.id(for: project.directory)),
            let marker = path.range(of: "/\(NotebookFormat.folderName)/projects/")
        else { return nil }
        return path[marker.upperBound...].split(separator: "/").first.map(String.init)
    }

    func add(_ kind: EntryKind, to project: ProjectModel) {
        guard let title = askTitle(kind) else { return }
        do {
            let file = try NotebookFormat.create(
                kind, title: title, in: project.notebookRoot,
                project: notebookProject(in: project),
                roadmap: notebookRoadmap(in: project),
                subject: notebookSubject(in: project))
            model.reload()
            let id =
                kind == .project
                ? file.deletingLastPathComponent().lastPathComponent
                : file.deletingPathExtension().lastPathComponent
            model.section = .board
            switch kind {
            case .project: model.selection = .project(id)
            case .task: model.selection = .task(id)
            case .roadmap, .memory, .run: model.selection = .page(id)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Removing a notebook entry. A project takes its tasks with it — a task filed under
    /// an id that no longer exists shows up nowhere and would never be worked.
    func remove(_ card: NotebookCard, in project: ProjectModel) {
        // The board the user asked from: the poll keeps running under the alert below.
        let cards = project.snapshot.cards
        let tasks = NotebookFormat.owned(by: card, in: cards).count - 1
        let alert = NSAlert()
        alert.messageText = "Move \u{201C}\(card.title)\u{201D} to the Trash?"
        alert.informativeText =
            card.kind == .project
            ? "The project folder, its memory and its \(tasks) task\(tasks == 1 ? "" : "s") go with it. "
                + "You can put them back from the Trash."
            : "You can put it back from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try NotebookFormat.remove(card, in: cards)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        // Anything on screen that was inside what just went to the Trash has no page left.
        let gone = Set(NotebookFormat.owned(by: card, in: cards).map(\.path))
        if let shown = model.selection?.card(in: cards),
            gone.contains(where: { shown.url.path == $0 || shown.url.path.hasPrefix($0 + "/") })
        {
            model.selection = .board
        }
        model.reload()
    }

    private func notebookRoadmap(in project: ProjectModel) -> String? {
        if case .page(let id) = model.selection,
            project.snapshot.cards.contains(where: { $0.id == id && $0.kind == .roadmap })
        {
            return id
        }
        let roadmaps = project.snapshot.cards.filter { $0.kind == .roadmap }
        return roadmaps.count == 1 ? roadmaps[0].id : nil
    }

    private func notebookSubject(in project: ProjectModel) -> String? {
        model.selection?.cardID ?? notebookProject(in: project)
    }
}

func pickDirectory(message: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = message
    return panel.runModal() == .OK ? panel.url?.path : nil
}

private func askTitle(_ kind: EntryKind) -> String? {
    let alert = NSAlert()
    alert.messageText = "New \(kind.displayName)"
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = "Title"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
}
