import SwiftUI
import UniformTypeIdentifiers
import YongkangCore

/// Putting an agent on work, from anywhere in the window: a ready task from any open project, or
/// anything described in a line — then the folders beyond that project it may read, and which CLI
/// runs it. The project it works in is the task's, so there is nothing to pick twice.
package struct NewAgentSheet: View {
    /// Every open project: the tasks listed, and the folders an agent can be handed.
    let projects: [Project]
    /// The project the window is in, which is listed first and is where "Anything" starts.
    let initial: Project.ID?
    let agent: AgentKind
    let found: Set<AgentKind>?
    let lookUp: () -> Void
    let startTask: (Project.ID, NotebookCard, AgentKind, [URL]) -> Void
    let startPrompt: (Project.ID, String, AgentKind, [URL]) -> Void
    let cancel: () -> Void

    private enum Mode { case task, anything }

    @State private var mode = Mode.task
    @State private var search = ""
    @State private var picked: (project: Project.ID, task: String)?
    @State private var home: Project.ID?
    @State private var prompt = ""
    @State private var reading: Set<URL> = []
    /// Folders added by hand, which are no open project.
    @State private var extra: [URL] = []
    @State private var choosingFolder = false
    @State private var chosen: AgentKind?

    package init(
        projects: [Project], initial: Project.ID?, agent: AgentKind, found: Set<AgentKind>?,
        lookUp: @escaping () -> Void,
        startTask: @escaping (Project.ID, NotebookCard, AgentKind, [URL]) -> Void,
        startPrompt: @escaping (Project.ID, String, AgentKind, [URL]) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.projects = projects
        self.initial = initial
        self.agent = agent
        self.found = found
        self.lookUp = lookUp
        self.startTask = startTask
        self.startPrompt = startPrompt
        self.cancel = cancel
    }

    package var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Agent").font(Typography.headline).foregroundStyle(Theme.tx)
                Text("One agent takes one task. It works in that task's project and reads only the folders you tick.")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            HStack(alignment: .top, spacing: 0) {
                work
                    .frame(width: 440)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
                settings
            }
            footer
        }
        .frame(width: 860, height: 580)
        .background(Theme.card)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result, !extra.contains(url) else { return }
            extra.append(url)
            reading.insert(url)
        }
        .onAppear { home = initial ?? projects.first?.id }
    }

    // MARK: - What it works on

    private var ordered: [Project] {
        projects.filter { $0.id == initial } + projects.filter { $0.id != initial }
    }

    private var work: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Works on", selection: $mode) {
                Text("A Task").tag(Mode.task)
                Text("Anything").tag(Mode.anything)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            switch mode {
            case .task: tasks
            case .anything: anything
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Find a task in any project", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ordered) { project in
                        let ready = project.readyTasks.filter {
                            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                                || $0.id.localizedCaseInsensitiveContains(search)
                        }
                        SectionLabel(project.name, trailing: ready.isEmpty ? "none ready" : "\(ready.count) ready")
                            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
                        ForEach(ready) { task in taskRow(task, in: project) }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.wellLine, lineWidth: 1))
        }
    }

    private func taskRow(_ task: NotebookCard, in project: Project) -> some View {
        let on = picked?.project == project.id && picked?.task == task.id
        return Button {
            picked = (project.id, task.id)
            home = project.id
            reading.remove(project.directory)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12)).foregroundStyle(on ? Theme.accent : Theme.tx3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(Typography.body(.semibold)).foregroundStyle(Theme.tx).lineLimit(1)
                    Text(task.id).font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowSelection(on)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var anything: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Project", selection: $home) {
                ForEach(ordered) { Text($0.name).tag(Optional($0.id)) }
            }
            TextEditor(text: $prompt)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.wellLine, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("What should it do?").font(Typography.body).foregroundStyle(Theme.tx3)
                            .padding(13).allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Where, what else, and who

    private var homeProject: Project? {
        let id = mode == .task ? picked?.project : home
        return projects.first { $0.id == id }
    }

    private var kind: AgentKind { chosen ?? agent }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Works in")
                if let homeProject {
                    folder(homeProject.directory, trailing: Text("edits").foregroundStyle(Theme.accent))
                        .cardSurface(radius: 10, padding: 0)
                } else {
                    Text("The task's project, once one is picked.").font(Typography.caption).foregroundStyle(Theme.tx3)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Can also read")
                let others = projects.map(\.directory).filter { $0 != homeProject?.directory } + extra
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element) { index, url in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        Toggle(isOn: binding(for: url)) { folder(url, trailing: nil) }
                            .toggleStyle(.checkbox)
                            .padding(.leading, 12)
                    }
                    if !others.isEmpty { Rectangle().fill(Theme.line).frame(height: 1) }
                    Button {
                        choosingFolder = true
                    } label: {
                        Label("A Folder That Is Not a Project…", systemImage: "plus")
                            .font(Typography.body).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.prose)
                }
                .cardSurface(radius: 10, padding: 0)
                .disabled(!kind.provider.readsOtherFolders)
                Text(
                    kind.provider.readsOtherFolders
                        ? "It reads these and changes nothing there: Review commits only the project it works in."
                        : "\(kind.displayName) can't be given other folders."
                )
                .font(Typography.caption).foregroundStyle(Theme.tx3)
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Agent")
                AgentPicker(
                    agent: Binding(get: { kind }, set: { chosen = $0 }), found: found, lookUp: lookUp,
                    purpose: "Agent for this work")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { reading.contains(url) },
            set: { if $0 { reading.insert(url) } else { reading.remove(url) } })
    }

    private func folder(_ url: URL, trailing: Text?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.tx3)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                Text(url.path).font(Typography.monoCaption).foregroundStyle(Theme.tx3)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 4)
            trailing?.font(Typography.caption(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    // MARK: - Start

    /// The folders it is actually handed: the ticked ones, less the one it works in.
    private var handed: [URL] {
        guard kind.provider.readsOtherFolders else { return [] }
        return (projects.map(\.directory) + extra).filter { reading.contains($0) && $0 != homeProject?.directory }
    }

    private var ready: Bool {
        guard found?.contains(kind) != false, homeProject != nil else { return false }
        switch mode {
        case .task: return picked != nil
        case .anything: return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(summary).font(Typography.body).foregroundStyle(Theme.prose).lineLimit(2)
            Spacer(minLength: 12)
            Button("Cancel", action: cancel).buttonStyle(.console).keyboardShortcut(.cancelAction)
            Button("Start Agent", action: start).buttonStyle(.consolePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Theme.well)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var summary: String {
        guard let homeProject else { return "Pick what it works on." }
        let reads = handed.map(\.lastPathComponent)
        let also = reads.isEmpty ? "" : " and reads " + reads.joined(separator: ", ")
        return "Edits \(homeProject.name)\(also). Nothing is committed until you approve it in Review."
    }

    private func start() {
        guard ready, let homeProject else { return }
        switch mode {
        case .task:
            guard let picked, let task = homeProject.cards.first(where: { $0.id == picked.task }) else { return }
            startTask(homeProject.id, task, kind, handed)
        case .anything:
            startPrompt(homeProject.id, prompt.trimmingCharacters(in: .whitespacesAndNewlines), kind, handed)
        }
    }
}
