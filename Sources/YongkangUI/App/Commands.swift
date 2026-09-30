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
    /// The default agent, which the toolbar's picker sets, for the sessions this menu starts.
    let agent: AgentKind
    let account: Account
    @AppStorage(Analytics.enabledKey) private var shareAnalytics = true

    var body: some Commands {
        // Under About, where a Mac app keeps its updates and its account.
        CommandGroup(after: .appInfo) { online }
        // Replacing `.newItem` is also what drops "New Window": the model and its
        // TerminalRegistry are app-wide, so a second window would take the first one's
        // terminals.
        CommandGroup(replacing: .newItem) { file }
        // The View menu, above the system's "Show Toolbar".
        CommandGroup(before: .toolbar) { view }
        CommandMenu("Agent") { agentMenu }
    }

    /// The project the selection is in, which is what every item below the first two acts on.
    private var project: ProjectModel? { model.entered }

    // MARK: - Yongkang

    /// Everything in the app that talks to a server (`Online/`). Each title flips rather than
    /// the item disappearing, like Show and Hide List.
    @ViewBuilder private var online: some View {
        let updates = Updates.shared
        // VS Code's "Restart to Update": the update is already downloaded, so this is one step.
        Button(updates.ready.map { "Restart to Update to \($0)" } ?? "Check for Updates…") {
            if updates.ready == nil { updates.check() } else { updates.restart() }
        }
        .disabled(!updates.available)
        Divider()
        Button(account.user.map { "Sign Out \($0.login ?? $0.email ?? "")" } ?? "Sign In with GitHub…") {
            guard account.user == nil else { return account.signOut() }
            Task {
                do { try await account.signIn() } catch { model.alert = .error(error) }
            }
        }
        .disabled(!account.available || account.signingIn)
        Toggle("Share Usage Analytics", isOn: $shareAnalytics)
        Divider()
    }

    // MARK: - File

    @ViewBuilder private var file: some View {
        // Both open from any screen: the sheet and the panel hang on `RootView`'s root. ⌘N is
        // New Agent's: putting an agent on work is what this window is for.
        Button("New Project…") { model.creatingProject = true }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        Button("Open Project…") { model.pickingFolder = true }
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
        // ⌘1–⌘3 in the rail's own order, so the number matches the icon's place in it. A
        // section needs no project: with none picked it shows its empty state.
        ForEach(Array(ConsoleSection.allCases.enumerated()), id: \.element) { index, section in
            Button(section.title) { model.section = section }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
        }
        Divider()
        // ⌘\ lives here now rather than on the toolbar button it used to hang from.
        Button(listHidden ? "Show List" : "Hide List") { listHidden.toggle() }
            .keyboardShortcut("\\")
        Toggle("Show Completed", isOn: showDone)
            .disabled(project == nil)
        Divider()
    }

    private var showDone: Binding<Bool> {
        Binding(get: { model.showDone }, set: { model.showDone = $0 })
    }

    // MARK: - Agent

    @ViewBuilder private var agentMenu: some View {
        Button("New Agent…") { model.startingAgent = true }
            .keyboardShortcut("n")
        Divider()
        Button("New Session") {
            guard let project else { return }
            model.selection = project.addSession(agent)
            model.section = .agents
        }
        .disabled(project == nil)
        OtherAgentMenu(title: "New Session With", agent: agent, found: model.foundAgents) { other in
            guard let project else { return }
            model.selection = project.addSession(other)
            model.section = .agents
        }
        .disabled(project == nil)
        Button("Assign Task") {
            guard let project, let task = model.assignableTask else { return }
            model.assign([task], in: project, agent: agent)
        }
        .disabled(model.assignableTask == nil)
        OtherAgentMenu(title: "Assign Task To", agent: agent, found: model.foundAgents) { other in
            guard let project, let task = model.assignableTask else { return }
            model.assign([task], in: project, agent: other)
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
    /// What "Assign Task" would hand over: the task the window has open, while it is
    /// neither finished nor already with a session — the same rule `TaskDetail`'s own button is
    /// disabled by.
    ///
    /// The board's Assign button sends the batch the user ticked, and those ticks are the
    /// board view's own state, which no menu can see. So the menu item works on the one task
    /// the selection names; picking several is still the board's job.
    var assignableTask: NotebookCard? {
        guard let project = entered, case .task(let id)? = selection,
            let card = project.cards.first(where: { $0.id == id && $0.kind == .task }),
            card.status != "done", !project.assignedTaskIDs.contains(card.id)
        else { return nil }
        return card
    }
}
