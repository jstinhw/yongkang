import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // The workflows are `ProjectModel` methods that return where to go, and `AppModel.go(to:)`
    // goes there; the ones that can end in a question set `model.alert`. What stays in the view
    // is what needs `@AppStorage`, and showing the alert and the folder picker.

    // MARK: - Alert

    /// The buttons for `model.alert`. An answer's work runs on the next turn of the main queue,
    /// after the alert has cleared `model.alert`, so an error it raises is shown rather than
    /// cleared along with the question.
    @ViewBuilder func alertActions(_ item: AlertItem) -> some View {
        switch item {
        case .message:
            Button("OK") {}
        case .confirm(_, _, let action, let perform):
            Button(action, role: .destructive) { DispatchQueue.main.async(execute: perform) }
            Button("Cancel", role: .cancel) {}
        case .title(_, let action, let create):
            TextField("Title", text: $typedTitle)
            Button(action) {
                let title = typedTitle
                typedTitle = ""
                DispatchQueue.main.async { create(title) }
            }
            Button("Cancel", role: .cancel) { typedTitle = "" }
        }
    }

    var alertShown: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }

    // MARK: - Projects

    /// The folder picked in the Open Project panel.
    func openProject(_ picked: Result<URL, any Error>) {
        let directory: URL
        do {
            directory = try picked.get()
        } catch {
            model.alert = .error(error)
            return
        }
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
    func createProject(at directory: URL, prompt: String, agent: AgentKind) {
        model.creatingProject = false
        if let existing = model.project(at: directory) {
            model.enter(existing)
            return
        }
        let project = model.open(directory)
        persist()
        model.enter(project)
        guard let started = model.entered, !started.hasNotebook else { return }
        model.go(to: started.startNotebookSetup(prompt, agent: agent))
    }

    func close(_ project: ProjectModel) {
        model.close(project)
        persist()
    }

    // MARK: - Review

    /// The failure is shown under the button rather than in an alert, so it comes back as text.
    /// The window stays on the task it just approved: the list beside it is the session's, and
    /// the next task waiting may belong to another one.
    func approve(_ task: SummaryTask, message: String, in project: ProjectModel) async -> String? {
        do {
            _ = try await project.approve(task, message: message)
            // Approving is the last thing an agent's chain was waiting on, so the session that
            // did it may have just become spent. Nothing else re-asks until the safety beat.
            model.endSpentSessions(in: project)
            return nil
        } catch {
            return error.reason
        }
    }

    func commit(_ message: String, in project: ProjectModel) async -> String? {
        do {
            model.selection = try await project.commit(message)
            return nil
        } catch {
            return error.reason
        }
    }
}
