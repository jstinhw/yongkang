import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // MARK: - Assigning

    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// list and the board cannot disagree about what a batch is. Also the one place that
    /// excludes work a still-open lead session already has, so a task never goes to two
    /// leads at once.
    ///
    /// A lead that is still running is talked to, not duplicated: the new batch is typed
    /// into its own terminal as a follow-up message, the same as telling a person who is
    /// already working "also pick these up" rather than hiring a second lead.
    func assign(_ tasks: [NotebookCard], in project: ProjectModel) {
        let batch = NotebookIndex.withBlockers(
            tasks, in: project.snapshot.cards, excluding: project.assignedTaskIDs)
        guard !batch.isEmpty else {
            guard !tasks.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "Nothing to assign"
            alert.informativeText =
                "Every task here is already done, or already has an Engineering "
                + "Lead on it — wait for that session to finish, or close it, before assigning again."
            alert.runModal()
            return
        }
        model.section = .agents
        if let lead = project.sessions.first(where: { $0.isEngineeringLead && !$0.exited }) {
            let leadAgent = lead.agent ?? .claude
            project.appendTaskIDs(batch.map(\.id), to: lead.id)
            model.pendingInput[lead.id] = NotebookFormat.additionalTasksPrompt(
                tasks: batch, sessionID: lead.id,
                agent: leadAgent)
            model.selection = .session(lead.id)
            return
        }
        // The id is minted here so the prompt can carry it: a lead that knows its own
        // session id can write it into any block it raises, and the answer comes back here.
        let id = UUID()
        addSession(
            agent, id: id, to: project,
            prompt: NotebookFormat.engineeringPrompt(tasks: batch, sessionID: id, agent: agent),
            title: "Engineering Lead", taskIDs: batch.map(\.id))
    }

    // MARK: - Blocks

    /// A gate starts a session whose only job is unblocking it. A proposal instead returns
    /// to its Product transcript, and only a ready proposal's create button sends approval.
    ///
    /// The page is deliberately not opened here. A browser tab that appears before the
    /// session has said anything lands the user on a token screen with no idea what it is
    /// for; the engineer explains first, and opens the page when the user is ready for it.
    func startUnblock(_ block: UserBlock, in project: ProjectModel) {
        guard !block.isProposal else {
            return openProposal(block, approve: block.proposalReady, in: project)
        }
        addSession(
            agent, to: project, prompt: NotebookFormat.unblockPrompt(block: block, agent: agent),
            title: "Unblock \(block.title)")
        model.section = .agents
    }

    /// A proposal belongs to the Product conversation that shaped it. Opening it is only
    /// navigation; the ready proposal's explicit create action is the approval message.
    func openProposal(_ block: UserBlock, approve: Bool, in project: ProjectModel) {
        let running =
            block.session.flatMap { id in
                project.sessions.first { $0.id == id && !$0.exited }
            } ?? project.sessions.last { isProduct($0) && !$0.exited }
        if let running {
            model.section = .agents
            model.selection = .session(running.id)
            if approve {
                model.pendingInput[running.id] =
                    "Approved. Create the roadmap changes, project, and tasks in this ready proposal."
            }
            return
        }
        let decision = approve ? "\nDecision: approve" : ""
        startProduct(NotebookFormat.relativePath(block.url) + decision, in: project)
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

    /// Product looks at the whole product and discusses what should come next. Blocks gets
    /// one link back to that transcript, then the finalized plan; the board stays unchanged
    /// until the user explicitly creates it.
    func startProductReview(in project: ProjectModel) {
        startProduct("review", in: project)
    }

    /// One product voice per project. A second session would propose against a board the
    /// first one is already rewriting, so a running one is talked to instead — the same
    /// rule the Engineering Lead follows for a second batch.
    func startProduct(_ arguments: String, in project: ProjectModel) {
        model.section = .agents
        if let running = project.sessions.first(where: { isProduct($0) && !$0.exited }) {
            let productAgent = running.agent ?? .claude
            model.pendingInput[running.id] = NotebookFormat.productPrompt(
                arguments: arguments, sessionID: running.id, agent: productAgent
            )
            model.selection = .session(running.id)
            return
        }
        let id = UUID()
        addSession(
            agent, id: id, to: project,
            prompt: NotebookFormat.productPrompt(arguments: arguments, sessionID: id, agent: agent),
            title: "Product")
    }

    /// Incubate mode: the app does not write the agent, a session does. It searches the
    /// skills this project can already load, fetches or writes what is missing, and adds
    /// the file to `.notebook/team/` — which the poll picks up as a new roster row, the
    /// same way any other notebook entry an agent writes turns up.
    func startIncubation(_ brief: String, in project: ProjectModel) {
        model.section = .agents
        addSession(
            agent, to: project,
            prompt: NotebookFormat.incubatePrompt(brief: brief, agent: agent),
            title: "New Agent")
    }

    private func isProduct(_ session: CodeSession) -> Bool {
        session.title == "Product" || session.title.hasPrefix("Product ")
    }

    // MARK: - Review

    /// Approving is committing: only this task's files and its records, then on to the
    /// next task waiting. Nothing is sent to the lead — it already marked the task done.
    func approve(_ task: SummaryTask, message: String, in project: ProjectModel) -> String? {
        let failure = GitChanges.commit(message: message, paths: task.commitPaths, in: project.directory)
        model.refreshChanges(force: true)
        guard failure == nil else { return failure }
        project.reviewDrafts[task.id] = nil
        model.selection = project.firstReview
        return nil
    }

    /// Sending a task back goes to the lead that holds it, typed into its terminal like any
    /// follow-up; with no lead running, a fresh one starts with the task and the comments.
    func requestChanges(on task: SummaryTask, in project: ProjectModel) {
        guard let draft = project.reviewDrafts[task.id], !draft.isEmpty else { return }
        let message = draft.message(taskID: task.id, title: task.title)
        let leads = project.sessions.filter { $0.isEngineeringLead && !$0.exited }
        if let lead = leads.first(where: { $0.taskIDs.contains(task.id) }) ?? leads.first {
            if !lead.taskIDs.contains(task.id) { project.appendTaskIDs([task.id], to: lead.id) }
            project.reviewDrafts[task.id] = nil
            model.section = .agents
            model.pendingInput[lead.id] = message
            model.selection = .session(lead.id)
            return
        }
        guard let card = project.snapshot.cards.first(where: { $0.id == task.id }) else { return }
        project.reviewDrafts[task.id] = nil
        model.section = .agents
        let id = UUID()
        addSession(
            agent, id: id, to: project,
            prompt: NotebookFormat.changeRequestPrompt(task: card, message: message, sessionID: id, agent: agent),
            title: "Engineering Lead", taskIDs: [task.id])
    }

    /// The review screen's one write to the repo. Staging and committing is all it does —
    /// no push, no merge, no branch — and only because the user pressed the button.
    func commit(_ message: String, in project: ProjectModel) -> String? {
        let failure = GitChanges.commit(message: message, in: project.directory)
        if failure == nil { model.selection = .review(file: nil) }
        model.refreshChanges(force: true)
        return failure
    }

    // MARK: - Sessions

    /// `id` is generated up front so the same id names both the CLI's `--session-id` and
    /// this session's own row — that is what lets its transcript be found again later, and
    /// what a caller passes in when the prompt itself has to name the session.
    func addSession(
        _ agent: AgentKind, id: UUID = UUID(), to project: ProjectModel,
        prompt: String? = nil, title: String? = nil, taskIDs: [String] = []
    ) {
        addSession(
            id: id, to: project, title: title ?? agent.displayName, icon: agent.systemImage,
            line: AgentCommand.line(
                directory: project.directory.path,
                agent: agent, prompt: prompt, sessionID: id,
                brief: title?.hasPrefix("Engineering Lead") == true,
                noCommit: title?.hasPrefix("Engineering Lead") == true),
            agent: agent, taskIDs: taskIDs)
    }

    func addSession(
        id: UUID = UUID(), to project: ProjectModel, title: String, icon: String, line: String,
        agent: AgentKind? = nil, taskIDs: [String] = []
    ) {
        project.addSession(id: id, title: title, icon: icon, line: line, agent: agent, taskIDs: taskIDs)
        // New sessions open their live CLI.
        model.selection = .session(id)
    }

    /// Every service in a project's repos, started at once — the board's "run the whole
    /// project" action.
    func runServices(_ card: NotebookCard, in project: ProjectModel) {
        runServices(Service.plan(for: card, in: project.directory), in: project)
    }

    /// One terminal per runnable service, all started together, because a front end
    /// reviewed without its service behind it is a page of errors. A service named after
    /// its repo (the common single-app case) keeps that name; one of several under a repo
    /// is named `repo/service`. Anything with nothing to run is named rather than skipped
    /// in silence.
    ///
    /// A service already running is shown, not started again: a second `npm run dev`
    /// fights the first one for its port, and the loser exits — which is exactly what was
    /// pushing a "default to :3000" preview onto whatever port the collision left it on.
    func runServices(
        _ steps: [(repo: String, directory: URL, services: [Service.Runnable])],
        in project: ProjectModel
    ) {
        let named = steps.flatMap { step in
            step.services.map { service in
                (
                    label: service.name == step.repo ? step.repo : "\(step.repo)/\(service.name)",
                    directory: service.directory, command: service.command
                )
            }
        }
        model.section = .agents
        for service in named where service.command != nil {
            let title = "Run \(service.label)"
            if let running = project.sessions.first(where: { $0.title == title }) {
                model.selection = .session(running.id)
                continue
            }
            addSession(
                to: project, title: title, icon: "play.circle",
                line: AgentCommand.line(directory: service.directory.path, run: service.command!))
        }
        let stuck = named.filter { $0.command == nil }
        guard !stuck.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = named.count == stuck.count ? "Nothing to run yet" : "Some services did not start"
        alert.informativeText = """
            No start command found in: \(stuck.map(\.label).joined(separator: ", ")).

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
