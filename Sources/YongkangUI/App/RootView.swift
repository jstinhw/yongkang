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
    /// The list column's width, dragged from its trailing divider, and whether it is
    /// collapsed. Both persist: a window you have sized once should come back that way.
    @AppStorage("listWidth") private var listWidth = 268.0
    @AppStorage("listHidden") private var listHidden = false
    /// The provider for every new agent session. Running sessions keep the provider they
    /// started with; switching a process underneath a live PTY is not possible.
    @AppStorage("agentKind") var agent = AgentKind.claude
    /// The list width the current resize drag started from; nil when nothing is dragging.
    @State private var dragBase: Double?
    /// The "New → Agent…" sheet, adding one file to `.notebook/team/`.
    @State var addingAgent = false
    /// The new-project sheet, opened from the Fleet page's own tile: a prompt, which is
    /// also what says where its folder goes.
    @State var creatingProject = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()
            chrome
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
                create: { creatingProject = true }, add: openProject,
                close: { if let project = model.project($0.id) { close(project) } }
            )
            .sheet(isPresented: $creatingProject) {
                NewProjectForm(
                    parent: projectsParent, create: createProject,
                    cancel: { creatingProject = false })
            }
        } else if let project = model.entered {
            HStack(spacing: 0) {
                // Above the list column: the rail's hover labels hang past its own width.
                Rail(
                    section: $model.section, badges: badges(for: project), leave: { model.leave() },
                    agentCount: project.value.onlineAgentCount,
                    listHidden: listHidden, toggleList: { listHidden.toggle() }
                )
                .zIndex(1)
                if !listHidden {
                    ProjectList(
                        section: model.section, project: project.value, width: listWidth,
                        selection: $model.selection,
                        showDone: model.showDone, changes: project.repo.changes,
                        assign: { assign($0, in: project) },
                        closeSession: { model.close($0, in: project) },
                        remove: { remove($0, in: project) }
                    )
                    .overlay(alignment: .trailing) { listResizer }
                }
                VStack(spacing: 0) {
                    topBar(for: project)
                    screen(for: project)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(isPresented: $addingAgent) {
                NewAgentForm(
                    directory: project.directory,
                    taken: project.snapshot.team.map(\.name),
                    save: { member in
                        do { try Team.write(member, root: project.notebookRoot) } catch {
                            NSAlert(error: error).runModal()
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

    /// The grab area over the list column's trailing divider. It sits in the overlay rather
    /// than the HStack so widening the column does not also move it by its own width.
    private var listResizer: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { $0 ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set() }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let base = dragBase ?? listWidth
                        dragBase = base
                        listWidth = min(560, max(200, base + drag.translation.width))
                    }
                    .onEnded { _ in dragBase = nil }
            )
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
        if CommandLine.arguments.contains("--attention-selftest") {
            runAttentionSelfTest()
            return
        }
        model.restore(openProjects)
        persist()
        model.reload()
    }

    /// Full app regression: actual Codex screen bytes travel through the PTY,
    /// representable callback, app state, banner and session navigation. No real agent.
    private func runAttentionSelfTest() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yk-attention-\(UUID())")
        let root = NotebookFormat.root(in: directory)
        _ = try! NotebookFormat.create(.task, title: "Trust screen test", in: root, project: nil)
        let output = directory.appendingPathComponent("trust.ansi")
        // Dev-only, run from a checkout: the capture is the test fixture, not a copy of it.
        let capture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Tests/YongkangCoreTests/Fixtures/codex/codex-0.154.0-trust-screen.ansi")
        try! FileManager.default.copyItem(at: capture, to: output)
        let project = model.open(directory)
        let session = CodeSession(
            title: "Engineering Lead", icon: "terminal",
            line: "cat \(AgentCommand.quoted(output.path)); exec sleep 30", agent: .codex)
        project.addSession(
            id: session.id, title: session.title, icon: session.icon, line: session.line, agent: session.agent)
        model.enter(project)
        model.section = .agents
        model.selection = .session(session.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            precondition(model.attention[session.id] != nil, "PTY callback must reach the app's banner state")
            guard let host = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
            else {
                preconditionFailure("attention selftest needs a rendered app window")
            }
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "/tmp/yongkang-attention-selftest.png"))
            openAttention(session, in: project)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                precondition(model.isVisible(session), "Open session must reveal the blocked terminal")
                model.close(project)
                try? FileManager.default.removeItem(at: directory)
                print("attention app selftest ok — banner rendered and blocked session opened")
                exit(0)
            }
        }
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
                    Text("Action required · \(project.name) · \(session.title)").font(Typo.text(12, .medium))
                    Text(model.attention[session.id] ?? "").font(Typo.text(11)).foregroundStyle(Theme.tx2)
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
