import AppKit
import SwiftUI
import YongkangCore

/// The menu bar. Everything here is also a button somewhere on screen, which is the point:
/// a shortcut hung on a button only works while that button is drawn, and a toolbar item
/// that scrolls out of a narrow window takes its shortcut with it. A menu item works from
/// any screen, and it is what Full Keyboard Access and VoiceOver read the app through.
///
/// Nothing is ever hidden. An item the window cannot act on is disabled, so the shortcut it
/// carries stays visible and the menu keeps the same shape everywhere in the app.
struct YongkangCommands: Commands {
    let model: AppModel
    /// The list column's switch, shared with `RootView` through UserDefaults rather than
    /// copied: `@AppStorage` is a view of one key, so both are the same switch.
    @Binding var listHidden: Bool
    /// The provider the toolbar's picker is on, for the sessions this menu starts.
    let agent: AgentKind

    var body: some Commands {
        // Replacing `.newItem` is also what drops "New Window": the model and its
        // TerminalRegistry are app-wide, so a second window would take the first one's
        // terminals. It frees ⌘N for the project the Fleet screen's tile describes.
        CommandGroup(replacing: .newItem) { file }
        // The View menu, above the system's "Show Toolbar".
        CommandGroup(before: .toolbar) { view }
        CommandMenu("Go") { go }
        CommandMenu("Agent") { agentMenu }
    }

    /// The project you are inside, which is what every item below the first two acts on.
    private var project: ProjectModel? { model.entered }

    // MARK: - File

    @ViewBuilder private var file: some View {
        // Both open from any screen: the sheet and the panel hang on `RootView`'s root, not
        // on the Fleet page that used to own them.
        Button("New Project…") { model.creatingProject = true }
            .keyboardShortcut("n")
        Button("Open Folder…") { model.pickingFolder = true }
            .keyboardShortcut("o")
        Divider()
        Button("Close Project") {
            guard let project else { return }
            model.close(project)
        }
        .disabled(project == nil)
        Button("Reveal in Finder") {
            guard let project else { return }
            NSWorkspace.shared.activateFileViewerSelecting([project.directory])
        }
        .disabled(project == nil)
    }

    // MARK: - View

    @ViewBuilder private var view: some View {
        // ⌘1–⌘5 in the rail's own order, so the number matches the icon's place in it.
        ForEach(Array(ConsoleSection.allCases.enumerated()), id: \.element) { index, section in
            Button(section.title) { model.section = section }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                .disabled(project == nil)
        }
        Divider()
        // ⌘\ lives here now rather than on the toolbar button it used to hang from.
        Button(listHidden ? "Show List" : "Hide List") { listHidden.toggle() }
            .keyboardShortcut("\\")
            .disabled(project == nil)
        Toggle("Show Completed", isOn: showDone)
            .disabled(project == nil)
        Divider()
    }

    private var showDone: Binding<Bool> {
        Binding(get: { model.showDone }, set: { model.showDone = $0 })
    }

    // MARK: - Go

    @ViewBuilder private var go: some View {
        // The only way back to every project since the rail's "YK" button went.
        Button("All Projects") { model.leave() }
            .keyboardShortcut("[")
            .disabled(project == nil)
    }

    // MARK: - Agent

    @ViewBuilder private var agentMenu: some View {
        Button("New Session") {
            guard let project else { return }
            model.selection = project.addSession(agent)
            model.section = .agents
        }
        .disabled(project == nil)
        Button("Assign to Lead") {
            guard let project, let task = model.assignableTask else { return }
            model.assign([task], in: project, agent: agent)
        }
        .disabled(model.assignableTask == nil)
        Button("Product Review") {
            guard let project else { return }
            model.go(to: project.startProductReview(agent: agent))
        }
        .disabled(project == nil)
    }
}

extension AppModel {
    /// What "Assign to Lead" would hand over: the task the window has open, while it is
    /// neither finished nor already with a lead — the same rule `TaskDetail`'s own button is
    /// disabled by.
    ///
    /// The board's Assign button sends the batch the user ticked, and those ticks are the
    /// board view's own state, which no menu can see. So the menu item works on the one task
    /// the selection names; picking several is still the board's job.
    var assignableTask: NotebookCard? {
        guard let project = entered, case .task(let id)? = selection,
            let card = project.snapshot.cards.first(where: { $0.id == id && $0.kind == .task }),
            card.status != "done", !project.assignedTaskIDs.contains(card.id)
        else { return nil }
        return card
    }
}
