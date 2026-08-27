import SwiftUI
import AppKit
import Combine

@main
struct ClaudeCodeApp: App {
    // ponytail: no folder is touched until the user picks one. Defaulting to $HOME made
    // claude scan the home folder and trip every TCC prompt (iCloud Drive, Music,
    // Documents) at launch. An NSOpenPanel choice carries intent, so macOS grants it.
    @State private var projects: [Project] = []
    /// nil = the all-projects screen; otherwise the project you are inside.
    @State private var entered: UUID?
    /// Notebook entries tag by file path, sessions by UUID string.
    @State private var selection: String?
    /// Which folders were open last time. Sessions are not restored — the agents died
    /// with the app — but the projects and their notebooks come back.
    @AppStorage("openProjects") private var openProjects = "[]"

    // ponytail: poll instead of an FSEvents watcher. The agents in the sidebar write
    // these files while you watch them; re-listing a few dozen paths every 2s is less
    // code than a recursive watcher and the tree is tiny. Revisit at thousands of files.
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            NotebookSelfTest.run()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            .frame(minWidth: 760, minHeight: 460)
            .task { restore() }
            .onReceive(tick) { _ in reload() }
        }
        .windowToolbarStyle(.unified)
    }

    private var enteredProject: Project? { projects.first { $0.id == entered } }

    // MARK: - Sidebar

    @ViewBuilder private var sidebar: some View {
        if let project = enteredProject {
            List(selection: $selection) {
                // A row rather than a toolbar icon: the way back has to be visible without
                // hunting, and a lone chevron next to the New menu is not.
                Button(action: leave) {
                    Label("All Projects", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[")

                rows(for: project)
            }
            .navigationTitle(project.name)
            .toolbar { addMenu(for: project) }
        } else {
            List {
                Section("Projects") {
                    ForEach(projects) { project in
                        Button { enter(project) } label: {
                            Label(project.name, systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Close Project") { close(project) } }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                Button("Open Project Folder…", systemImage: "plus", action: openProject)
                    .keyboardShortcut("n")
            }
        }
    }

    @ViewBuilder private func rows(for project: Project) -> some View {
        Section("Notebook") {
            if project.hasNotebook {
                Label("Board", systemImage: "rectangle.split.3x1")
                    .tag(boardID(project))
                OutlineGroup(project.entries, children: \.children) { entry in
                    Label(entry.title, systemImage: entry.icon)
                        .tag(entry.id)
                        .contextMenu { entryMenu(entry, in: project) }
                }
            } else {
                // The shape of what the agent is about to write. Untagged, so these are
                // dimmed and unselectable until the folders exist and the tree replaces them.
                ForEach(NotebookFormat.folders, id: \.self) { folder in
                    Label(folder, systemImage: NotebookLoader.icon(forFolder: folder))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        let preview = previewRows(for: project)
        if !preview.isEmpty {
            Section("Preview") {
                ForEach(preview, id: \.id) { row in
                    Label(row.repo, systemImage: "play.rectangle")
                        .tag(row.id)
                }
            }
        }
        Section("Sessions") {
            ForEach(project.sessions) { session in
                sessionRow(session)
                    .tag(session.id.uuidString)
                    .contextMenu {
                        Button("Close Session") { close(session, in: project) }
                    }
            }
            if project.sessions.isEmpty {
                Label("Notebook Setup", systemImage: AgentKind.claude.systemImage)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Right-clicking a task in the tree assigns it, without going by way of the board.
    @ViewBuilder private func entryMenu(_ entry: NotebookEntry, in project: Project) -> some View {
        if let card = project.cards.first(where: { $0.url.path == entry.url.path }), card.kind == .task {
            Button("Assign to Engineering Lead", systemImage: "person.2") {
                assign([card], in: project)
            }
            .disabled(card.status == "done" || project.assignedTaskIDs.contains(card.id))
        }
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        }
    }

    /// A session's tasks, shown so you can tell what a lead is on without opening its
    /// terminal. Two lines only for a session that was actually handed work.
    @ViewBuilder private func sessionRow(_ session: CodeSession) -> some View {
        if session.taskIDs.isEmpty {
            Label(session.title, systemImage: session.icon)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label(session.title, systemImage: session.icon)
                Text(session.taskIDs.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// Blockers come along whichever way the tasks were picked — expanding here means the
    /// sidebar and the board cannot disagree about what a batch is. Also the one place that
    /// excludes work a still-open lead session already has, so a task never goes to two
    /// leads at once.
    private func assign(_ tasks: [NotebookCard], in project: Project) {
        let batch = NotebookIndex.withBlockers(tasks, in: project.cards, excluding: project.assignedTaskIDs)
        guard !batch.isEmpty else {
            guard !tasks.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "Nothing to assign"
            alert.informativeText = "Every task here is already done, or already has an Engineering "
                + "Lead on it — wait for that session to finish, or close it, before assigning again."
            alert.runModal()
            return
        }
        addSession(.claude, to: project,
                   prompt: NotebookFormat.engineeringPrompt(tasks: batch),
                   title: "Engineering Lead", taskIDs: batch.map(\.id))
    }

    private func addMenu(for project: Project) -> some View {
        Menu("New", systemImage: "plus") {
            Section("Session") {
                Button("Claude Code", systemImage: AgentKind.claude.systemImage) {
                    addSession(.claude, to: project)
                }
                Button("Codex", systemImage: AgentKind.codex.systemImage) {
                    addSession(.codex, to: project)
                }
            }
            Section("Notebook") {
                Button("Roadmap Entry…", systemImage: "map") { add(.roadmap, to: project) }
                Button("Project…", systemImage: "shippingbox") { add(.project, to: project) }
                Button("Task…", systemImage: "checkmark.circle") { add(.task, to: project) }
                Button("Memory…", systemImage: "brain") { add(.memory, to: project) }
                    .disabled(notebookProject(in: project) == nil)
            }
            Divider()
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.directory])
            }
            Button("Close Project", systemImage: "xmark") { close(project) }
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ZStack {
            // ponytail: every terminal stays mounted for the life of the app. Leaving a
            // project, switching rows, or browsing the home screen must not tear down a
            // running agent's PTY, so these are hidden rather than removed.
            ForEach(projects) { project in
                ForEach(project.sessions) { session in
                    AgentTerminal(line: session.line, label: session.title)
                        .opacity(isVisible(session) ? 1 : 0)
                        .allowsHitTesting(isVisible(session))
                        .accessibilityHidden(!isVisible(session))
                }
            }
            if entered == nil {
                ProjectsHome(projects: projects, enter: enter, add: openProject, close: close)
            } else if let project = needsIntake {
                // An empty project has nothing to click, so it asks what it is instead.
                ProjectIntake(project: project) { description in
                    addSession(.claude, to: project,
                               prompt: NotebookFormat.onboardingPrompt(description: description),
                               title: "Notebook Setup")
                }
            } else if let project = enteredProject, selection == boardID(project) {
                NotebookBoard(
                    cards: project.cards,
                    directory: project.directory,
                    assigned: project.assignedTaskIDs,
                    open: { url in selection = NotebookEntry.id(for: url) },
                    assign: { tasks in assign(tasks, in: project) },
                    run: { card in runServices(card, in: project) }
                )
            } else if let project = enteredProject, let step = previewStep(in: project) {
                ProjectPreview(repo: step.repo, services: step.services,
                               run: { runServices([step], in: project) })
                    .id(selection)
            } else if let entry = selectedEntry {
                NotebookEditor(entry: entry).id(entry.id)
            } else if selection == nil {
                Text("Pick a notebook entry, or start a session with +")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isVisible(_ session: CodeSession) -> Bool {
        entered != nil && selection == session.id.uuidString
    }

    /// A project with no notebook and no agent yet — the one case that starts a chat.
    private var needsIntake: Project? {
        enteredProject.flatMap { $0.hasNotebook || !$0.sessions.isEmpty ? nil : $0 }
    }

    private var selectedEntry: NotebookEntry? {
        guard let selection, let project = enteredProject else { return nil }
        return NotebookLoader.find(selection, in: project.entries)
    }

    // MARK: - Projects

    private func openProject() {
        guard let path = pickDirectory(
            message: "Agents run in this folder and its notebook lives in \(NotebookFormat.folderName)/."
        ) else { return }
        let directory = URL(fileURLWithPath: path)
        if let existing = projects.first(where: { $0.directory.path == directory.path }) {
            enter(existing)
            return
        }
        let project = Project(directory: directory,
                              entries: NotebookLoader.load(root: NotebookFormat.root(in: directory)))
        projects.append(project)
        persist()
        enter(project)
    }

    /// Reopens last session's folders, dropping any that have since been moved away.
    private func restore() {
        guard projects.isEmpty else { return }
        projects = OpenProjects.decode(openProjects)
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { path in
                let directory = URL(fileURLWithPath: path)
                return Project(directory: directory,
                               entries: NotebookLoader.load(root: NotebookFormat.root(in: directory)))
            }
        persist()
    }

    private func persist() {
        openProjects = OpenProjects.encode(projects.map(\.directory.path))
    }

    private func enter(_ project: Project) {
        entered = project.id
        selection = nil
        reload()
    }

    private func leave() {
        entered = nil
        selection = nil
    }

    private func close(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        persist()
        if entered == project.id { leave() }
    }

    private func boardID(_ project: Project) -> String { "board:\(project.id.uuidString)" }

    private func previewID(_ project: Project, _ directory: URL) -> String {
        "preview:\(project.id.uuidString):\(directory.path)"
    }

    /// One sidebar row per repo actually on disk, deduped across every notebook project.
    private func previewRows(for project: Project)
        -> [(id: String, repo: String, directory: URL, services: [Service.Runnable])] {
        let steps = project.cards.filter { $0.kind == .project }
            .flatMap { Service.plan(for: $0, in: project.directory) }
        return Service.dedupedByDirectory(steps).map { step in
            (id: previewID(project, step.directory), repo: step.repo,
             directory: step.directory, services: step.services)
        }
    }

    /// The repo a preview tag points at, or nil if `selection` is not one.
    private func previewStep(in project: Project)
        -> (repo: String, directory: URL, services: [Service.Runnable])? {
        guard let selection else { return nil }
        guard let row = previewRows(for: project).first(where: { $0.id == selection }) else { return nil }
        return (row.repo, row.directory, row.services)
    }

    private func reload() {
        for index in projects.indices {
            let entries = NotebookLoader.load(root: projects[index].notebookRoot)
            if entries != projects[index].entries { projects[index].entries = entries }
            // Only the project you are inside pays for reading frontmatter.
            guard projects[index].id == entered else { continue }
            let cards = NotebookIndex.load(root: projects[index].notebookRoot)
            if cards != projects[index].cards { projects[index].cards = cards }
        }
    }

    // MARK: - Sessions

    private func addSession(_ agent: AgentKind, to project: Project,
                            prompt: String? = nil, title: String? = nil, taskIDs: [String] = []) {
        addSession(to: project, title: title ?? agent.displayName, icon: agent.systemImage,
                   line: AgentCommand.line(directory: project.directory.path,
                                           agent: agent, prompt: prompt),
                   taskIDs: taskIDs)
    }

    private func addSession(to project: Project, title: String, icon: String, line: String,
                            taskIDs: [String] = []) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        // Second "Engineering Lead" becomes "Engineering Lead 2" — identical sidebar rows
        // are unusable, and several leads at once is a normal thing to want.
        let taken = projects[index].sessions.filter { $0.title == title || $0.title.hasPrefix(title + " ") }.count
        let name = taken == 0 ? title : "\(title) \(taken + 1)"
        projects[index].sessions.append(CodeSession(title: name, icon: icon, line: line, taskIDs: taskIDs))
        selection = projects[index].sessions.last?.id.uuidString
    }

    /// Every service in a project's repos, started at once — the board's "run the whole
    /// project" action.
    private func runServices(_ card: NotebookCard, in project: Project) {
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
    private func runServices(_ steps: [(repo: String, directory: URL, services: [Service.Runnable])],
                             in project: Project) {
        let named = steps.flatMap { step in
            step.services.map { service in
                (label: service.name == step.repo ? step.repo : "\(step.repo)/\(service.name)",
                 directory: service.directory, command: service.command)
            }
        }
        for service in named where service.command != nil {
            let title = "Run \(service.label)"
            if let running = project.sessions.first(where: { $0.title == title }) {
                selection = running.id.uuidString
                continue
            }
            addSession(to: project, title: title, icon: "play.circle",
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

    private func close(_ session: CodeSession, in project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].sessions.removeAll { $0.id == session.id }
        if selection == session.id.uuidString { selection = nil }
    }

    // MARK: - Notebook entries

    /// The `.notebook/projects/<id>` the selection sits in — memory has to land in one.
    private func notebookProject(in project: Project) -> String? {
        guard let selection,
              selection.hasPrefix(NotebookEntry.id(for: project.directory)),
              let marker = selection.range(of: "/\(NotebookFormat.folderName)/projects/")
        else { return nil }
        return selection[marker.upperBound...].split(separator: "/").first.map(String.init)
    }

    private func add(_ kind: EntryKind, to project: Project) {
        guard let title = askTitle(kind) else { return }
        do {
            let file = try NotebookFormat.create(kind, title: title, in: project.notebookRoot,
                                                 project: notebookProject(in: project))
            reload()
            // Projects select their folder row, which opens project.md.
            selection = NotebookEntry.id(for: kind == .project ? file.deletingLastPathComponent() : file)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private func pickDirectory(message: String) -> String? {
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
