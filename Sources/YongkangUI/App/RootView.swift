import AppKit
import Combine
import SwiftUI
import YongkangCore

/// The window. It draws what `AppModel` and the entered `ProjectModel` hold and turns the
/// user's gestures into calls on them. What it keeps itself is layout, the sheets it has
/// open, and the settings `@AppStorage` persists.
struct RootView: View {
    @Bindable var model: AppModel
    /// Which folders were open last time. Sessions are not restored — the agents died
    /// with the app — but the projects and their notebooks come back.
    @AppStorage("openProjects") private var openProjects = "[]"
    @AppStorage("openSessions") private var openSessions = "{}"
    /// Whether the list column is shut, and how wide it is when it is not. Both persist: a
    /// window you have shaped once should come back that way. `listWidth` is the key the old
    /// bundle's defaults are migrated under, from when the list last remembered its width.
    @AppStorage("listHidden") var listHidden = false
    @AppStorage("listWidth") private var listWidth = Double(Theme.listWidth)
    /// The provider for every new agent session. Running sessions keep the provider they
    /// started with; switching a process underneath a live PTY is not possible.
    @AppStorage("agentKind") var agent = AgentKind.claude
    /// The "New → Agent…" sheet, adding one file to `.notebook/team/`.
    @State var addingAgent = false
    /// What the title prompt's field holds while `model.alert` asks for one.
    @State var typedTitle = ""
    /// The project the window was inside when it last closed, by path, and where in it it
    /// was. `@AppStorage("openProjects")` reopens the folders; these three are the rest of
    /// the address. See `restore()`.
    @SceneStorage("enteredProject") private var enteredProject = ""
    @SceneStorage("section") private var storedSection = ConsoleSection.board
    @SceneStorage("route") private var storedRoute = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()
            chrome
        }
        // The two doors into a project hang on the window, not on the Fleet page that used to
        // own them, so the File menu can open either from inside a project as well.
        .fileImporter(isPresented: $model.pickingFolder, allowedContentTypes: [.folder], onCompletion: openProject)
        .fileDialogMessage("Agents run in this folder and its notebook lives in \(NotebookFormat.folderName)/.")
        .sheet(isPresented: $model.creatingProject) {
            NewProjectForm(
                parent: projectsParent, agent: agent, found: model.foundAgents, lookUp: model.lookUpAgents,
                create: createProject, cancel: { model.creatingProject = false })
        }
        .sheet(isPresented: $model.startingAgent) {
            NewAgentSheet(
                projects: model.projects.map(\.value), initial: model.entered?.id, agent: agent,
                found: model.foundAgents, lookUp: model.lookUpAgents,
                startTask: { id, task, kind, reading in
                    guard let project = model.project(id) else { return }
                    model.startingAgent = false
                    model.enter(project)
                    model.assign([task], in: project, agent: kind, reading: reading)
                },
                startPrompt: { id, prompt, kind, reading in
                    guard let project = model.project(id) else { return }
                    model.startingAgent = false
                    model.section = .agents
                    let note = NotebookFormat.readingNote(reading.map(\.path))
                    model.enter(project, at: project.addSession(kind, prompt: prompt + note, reading: reading))
                },
                cancel: { model.startingAgent = false })
        }
        .alert(model.alert?.title ?? "", isPresented: alertShown, presenting: model.alert) { item in
            alertActions(item)
        } message: { item in
            Text(item.detail)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { attentionNotices }
        .onChange(of: agent, initial: true) { model.agent = agent }
        .onReceive(NotificationCenter.default.publisher(for: AgentNotifications.openSession)) { note in
            guard let id = note.object as? String else { return }
            for project in model.projects {
                if let session = project.sessions.first(where: { $0.id.uuidString == id }) {
                    openAttention(session, in: project)
                }
            }
        }
        // Every project's FSEvents stream is torn down by hand: the `@MainActor` models that own
        // them get a nonisolated `deinit`, and nothing else would ever call `stop()`.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stop()
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1120, minHeight: 680)
        .task { await restore() }
        .onChange(of: model.section) {
            model.openSectionDefault()
            storedSection = model.section
        }
        .onChange(of: model.selection) {
            storedRoute = model.selection?.stored ?? ""
        }
        .onChange(of: model.entered?.directory.path) { enteredProject = model.entered?.directory.path ?? "" }
    }

    private var attentionNotices: some View {
        VStack(spacing: 0) {
            ForEach(model.projects) { project in
                AttentionNotices(model: model, project: project)
            }
        }
    }

    private func openAttention(_ session: CodeSession, in project: ProjectModel) {
        model.openAttention(session, in: project)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Chrome

    /// The rail, the sidebar of every project, and the screen. There is no page of projects to
    /// come back to any more: with nothing picked, the screen is empty and the sidebar is the
    /// way in.
    private var chrome: some View {
        HStack(spacing: 0) {
            // The rail stays apart from the list: it is the one piece of navigation that
            // never changes. It is also drawn above the list column, because its hover
            // labels hang past its own width.
            // Picking a section is asking for its list, so a click brings a hidden list
            // back — even on the section already showing, where nothing else would change.
            Rail(
                section: Binding(
                    get: { model.section },
                    set: {
                        model.section = $0
                        listHidden = false
                    }), badges: badges,
                agentCount: model.projects.reduce(0) { $0 + $1.value.onlineAgentCount }
            )
            .zIndex(1)
            // A divider of our own, not `NavigationSplitView`: on macOS 26 a native sidebar
            // floats as an inset glass panel, 8pt clear of the rail, the top and the bottom, with
            // a shadow over the screen, and no style turns that off. Nor `HSplitView`, which
            // opens a pane at its minimum and hands back no width: the list could be neither
            // dragged narrower than it opened, nor dragged shut, nor come back at the width it
            // was left at. `ListDivider` does all three.
            HStack(spacing: 0) {
                if !listHidden {
                    ProjectSidebar(
                        section: model.section, projects: sidebarProjects,
                        entered: model.entered?.id, selection: model.selection,
                        open: { id, route, section in
                            guard let project = model.project(id) else { return }
                            model.section = section
                            model.enter(project, at: route)
                        },
                        create: { model.creatingProject = true }, add: { model.pickingFolder = true },
                        closeSession: { id, session in
                            if let project = model.project(id) { model.close(session, in: project) }
                        },
                        close: { id in if let project = model.project(id) { close(project) } },
                        openUsage: { model.openUsage() }
                    )
                    .frame(width: min(max(listWidth, ListDivider.minWidth), ListDivider.maxWidth))
                }
                ListDivider(width: $listWidth, hidden: $listHidden)
                    // Above the screen, so the half of its grip that overhangs the screen still
                    // takes the drag.
                    .zIndex(1)
                work
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
                    .layoutPriority(1)
                    .navigationTitle(title(for: model.entered))
                    .navigationSubtitle(subtitle(for: model.entered))
                    .toolbar { toolbar(for: model.entered) }
            }
        }
        .sheet(isPresented: $addingAgent) {
            if let project = model.entered {
                NewAgentForm(
                    directory: project.directory,
                    taken: project.snapshot.team.map(\.name),
                    save: { member in
                        do { try Team.write(member, root: project.notebookRoot) } catch {
                            model.alert = .error(error)
                        }
                        addingAgent = false
                        model.reload()
                    },
                    incubate: { brief in
                        addingAgent = false
                        model.go(to: project.startIncubation(brief, agent: agent))
                    },
                    cancel: { addingAgent = false }
                )
            }
        }
    }

    /// Every open project with its agents, as the sidebar lists them.
    private var sidebarProjects: [SidebarProject] {
        model.projects.map { project in
            SidebarProject(
                project: project.value, summary: project.summary, asking: model.attention, missing: project.missing)
        }
    }

    /// Usage, which is every project's; the selected project's screen; or the empty one.
    @ViewBuilder private var work: some View {
        if model.showsUsage {
            UsageBoard(
                projects: model.projects.map(\.value),
                signature: model.projects.map(\.usageSignature).joined(separator: "|"),
                open: { id, route in
                    guard let project = model.project(id) else { return }
                    model.enter(project, at: route)
                })
        } else if let project = model.entered {
            screen(for: project)
        } else {
            NothingPicked(
                hasProjects: !model.projects.isEmpty,
                create: { model.creatingProject = true }, add: { model.pickingFolder = true })
        }
    }

    /// A dot on the rail for what is about the user rather than the work, across every project:
    /// amber when anything needs you, green when work waits for your review, and the running
    /// colour while agents are at work.
    private var badges: [ConsoleSection: Color] {
        let rows = sidebarProjects.flatMap(\.rows)
        if rows.contains(where: { $0.state == .needsYou }) { return [.agents: Theme.amber] }
        if rows.contains(where: { $0.state == .review }) { return [.agents: Theme.green] }
        if rows.contains(where: { $0.state == .working }) { return [.agents: Theme.accent] }
        return [:]
    }

    // MARK: - Projects

    /// The last run's window, in order: its folders, then the project it was inside and the
    /// page it had open.
    ///
    /// The read is awaited rather than fired off, because a route names a card, a block or a
    /// team member, and none of those exist until a notebook has been read — validated any
    /// earlier, every stored route would look stale on every launch.
    private func restore() async {
        guard model.projects.isEmpty else { return }
        model.restore(openProjects)
        persist()
        // Resumed before the hook goes in, so the stored list is read whole, not rewritten one
        // session at a time as each comes back.
        await model.resumeSessions(openSessions)
        model.sessionsChanged = { openSessions = model.storedSessions }
        model.sessionsChanged()
        model.start()
        model.lookUpAgents()
        await model.reloadNow()
        model.restore(entered: enteredProject, section: storedSection, route: Route(stored: storedRoute))
        // After the read, which is what finds the demos; not awaited, since a server booting
        // must not hold the window back.
        Task { await model.serveDemos() }
    }

    func persist() {
        openProjects = model.storedProjects
    }
}

/// One project's "Action required" notices, in their own view so a poll that changes this
/// project's sessions re-renders its notices and not the window around them.
private struct AttentionNotices: View {
    let model: AppModel
    let project: ProjectModel

    var body: some View {
        ForEach(project.sessions.filter { model.attention[$0.id] != nil && !$0.exited }) { session in
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Action required · \(project.name) · \(session.title)").font(Typography.body(.medium))
                    Text(model.attention[session.id] ?? "").font(Typography.caption).foregroundStyle(Theme.tx2)
                }
                Spacer()
                Button("Open session") {
                    model.openAttention(session, in: project)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.consolePrimary)
            }
            .padding(14)
            .background(Theme.panel)
        }
    }
}

/// The screen while nothing is picked. With projects open the sidebar is the way in; with none,
/// the two ways a project arrives are here, since the sidebar has nothing to click yet.
package struct NothingPicked: View {
    let hasProjects: Bool
    let create: () -> Void
    let add: () -> Void

    package init(hasProjects: Bool, create: @escaping () -> Void, add: @escaping () -> Void) {
        self.hasProjects = hasProjects
        self.create = create
        self.add = add
    }

    package var body: some View {
        VStack(spacing: 14) {
            Text(hasProjects ? "Pick a project or an agent on the left." : "Add a project to start.")
                .font(Typography.body).foregroundStyle(Theme.tx3)
            if !hasProjects {
                HStack(spacing: 10) {
                    Button("Describe a New Project…", action: create).buttonStyle(.consolePrimary)
                    Button("Open a Folder…", action: add).buttonStyle(.console)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
