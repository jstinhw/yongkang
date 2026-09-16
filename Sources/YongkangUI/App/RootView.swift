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
    /// Whether the list column is collapsed. It persists: a window you have collapsed once
    /// should come back that way. Its *width* no longer does — the split view owns that, and
    /// drags it from a real divider.
    @AppStorage("listHidden") var listHidden = false
    /// The provider for every new agent session. Running sessions keep the provider they
    /// started with; switching a process underneath a live PTY is not possible.
    @AppStorage("agentKind") var agent = AgentKind.claude
    /// The "New → Agent…" sheet, adding one file to `.notebook/team/`.
    @State var addingAgent = false
    /// What the title prompt's field holds while `model.alert` asks for one.
    @State var typedTitle = ""

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
                parent: projectsParent, create: createProject,
                cancel: { model.creatingProject = false })
        }
        .alert(model.alert?.title ?? "", isPresented: alertShown, presenting: model.alert) { item in
            alertActions(item)
        } message: { item in
            Text(item.detail)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { attentionNotices }
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
        .task { restore() }
        .onChange(of: model.section) { model.openSectionDefault() }
        // The transcript follows the selection rather than the poll: a row that opens an
        // agent must not leave the one before it on screen for up to two seconds under
        // the new agent's name. Every screen that opens one is covered by this — the
        // list column and the overview's "Running now" cards included.
        .onChange(of: model.selection) { model.reloadAgentTranscript() }
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

    @ViewBuilder private var chrome: some View {
        if model.entered == nil {
            ProjectsHome(
                projects: model.projects.map(\.value),
                enter: { if let project = model.project($0.id) { model.enter(project) } },
                create: { model.creatingProject = true }, add: { model.pickingFolder = true },
                close: { if let project = model.project($0.id) { close(project) } }
            )
        } else if let project = model.entered {
            HStack(spacing: 0) {
                // The rail stays outside the split view. A native sidebar cannot hold both it
                // and the list without reading as two sidebars, and the rail is the one piece
                // of navigation that never changes. It is also drawn above the list column,
                // because its hover labels hang past its own width.
                Rail(
                    section: $model.section, badges: badges(for: project), leave: { model.leave() },
                    agentCount: project.value.onlineAgentCount
                )
                .zIndex(1)
                NavigationSplitView(columnVisibility: columns) {
                    ProjectList(
                        section: model.section, project: project.value,
                        selection: $model.selection,
                        showDone: model.showDone, changes: project.repo.changes, summary: project.summary,
                        assign: { model.assign($0, in: project, agent: agent) },
                        closeSession: { model.close($0, in: project) },
                        remove: { model.remove($0, in: project) }
                    )
                    // The three numbers the hand-rolled resizer used to clamp to, handed to
                    // the split view instead. Nothing adds them up any more: the panes'
                    // geometry is the containers' own.
                    .navigationSplitViewColumnWidth(min: 200, ideal: Theme.listWidth, max: 560)
                    // One toggle, not two: ours carries ⌘\ and sits where the system's did.
                    .toolbar(removing: .sidebarToggle)
                } detail: {
                    screen(for: project)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.bg)
                        .navigationTitle(title(for: project))
                        .navigationSubtitle(subtitle(for: project))
                        .toolbar { toolbar(for: project) }
                }
            }
            .sheet(isPresented: $addingAgent) {
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

    /// The split view's state, read and written through the one thing that persists. Collapsing
    /// by dragging the divider and collapsing with ⌘\ are then the same switch, and neither can
    /// disagree with what comes back on the next launch.
    private var columns: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { NavigationSplitViewVisibility(listHidden: listHidden) },
            set: { listHidden = $0.listHidden })
    }

    /// A dot on the rail for the two things that are about the user rather than the work:
    /// something waiting on them, and something an agent has left to be read.
    private func badges(for project: ProjectModel) -> [ConsoleSection: Color] {
        var badges: [ConsoleSection: Color] = [:]
        if project.snapshot.blocks.contains(where: \.waiting) { badges[.blocks] = Theme.amber }
        if project.sessions.contains(where: { !$0.activeSubagents.isEmpty }) {
            badges[.agents] = Theme.accent
        }
        // Lit for work waiting on the user's approval, not for any edit in the tree.
        if !project.summary.waiting.isEmpty { badges[.review] = Theme.green }
        return badges
    }

    // MARK: - Projects

    private func restore() {
        guard model.projects.isEmpty else { return }
        model.restore(openProjects)
        persist()
        model.reload()
        model.start()
    }

    func persist() {
        openProjects = model.storedProjects
    }
}

extension NavigationSplitViewVisibility {
    /// ⌘\ has two positions, and the window only ever has two columns, so the split view's
    /// four-way state is stored as the one bit that survives a relaunch. `.doubleColumn` is
    /// what SwiftUI hands back when the divider is dragged open, and means the same as `.all`
    /// here: the list is showing.
    init(listHidden: Bool) {
        self = listHidden ? .detailOnly : .all
    }

    var listHidden: Bool { self == .detailOnly }
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
