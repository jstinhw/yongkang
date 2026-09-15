import AppKit
import SwiftUI
import YongkangCore

extension RootView {
    // MARK: - Workflows

    // The workflows are `ProjectModel` methods that return where to go, and `AppModel.go(to:)`
    // goes there. What stays in the view is the prompts and alerts that need a window.

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
        model.go(to: destination)
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
        model.selection = started.addSession(
            agent, prompt: NotebookFormat.onboardingPrompt(description: prompt), title: "Notebook Setup")
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

    // MARK: - Services

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
        model.go(to: run.destination)
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

    func add(_ kind: EntryKind, to project: ProjectModel) {
        guard let title = askTitle(kind) else { return }
        do {
            let destination = try project.add(kind, title: title, selection: model.selection)
            model.reload()
            model.go(to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

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
            if let route = try project.remove(card, from: cards, selection: model.selection) {
                model.selection = route
            }
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        model.reload()
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
