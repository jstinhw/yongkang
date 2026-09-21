import Foundation
import YongkangCore

/// Something the window has to tell the user, or ask before it acts, held in `AppModel.alert`
/// for `RootView` to show. Nothing waits for the answer: the modal alerts before it did, and held
/// up the main run loop the terminals draw on, the poll runs on, and the registry types from.
enum AlertItem {
    /// Only an OK button.
    case message(String, detail: String = "")
    /// `perform` runs when the user picks `action`; Cancel does nothing.
    case confirm(String, detail: String, action: String, perform: @MainActor @Sendable () -> Void)
    /// A title to type. `create` gets what was typed when the user picks Create.
    case title(String, create: @MainActor @Sendable (String) -> Void)

    static func error(_ error: any Error) -> AlertItem {
        let error = error as NSError
        return .message(error.localizedDescription, detail: error.localizedRecoverySuggestion ?? "")
    }

    var title: String {
        switch self {
        case .message(let title, _), .confirm(let title, _, _, _), .title(let title, _): return title
        }
    }

    var detail: String {
        switch self {
        case .message(_, let detail), .confirm(_, let detail, _, _): return detail
        case .title: return ""
        }
    }
}

// The workflows that can end in a question or an explanation rather than somewhere to go.
extension AppModel {
    func assign(_ tasks: [NotebookCard], in project: ProjectModel, agent: AgentKind, reading: [URL] = []) {
        guard let destination = project.assign(tasks, agent: agent, reading: reading) else {
            guard !tasks.isEmpty else { return }
            alert = .message(
                "Nothing to assign",
                detail: "Every task here is already done, or already has a session on it — "
                    + "wait for that session to finish, or close it, before assigning again.")
            return
        }
        go(to: destination)
    }

    func runServices(
        _ steps: [ServicePlan],
        in project: ProjectModel
    ) {
        let run = project.runServices(steps)
        go(to: run.destination)
        guard !run.unstarted.isEmpty else { return }
        alert = .message(
            // No route means no service was started or shown: none of them had a command.
            run.destination.route == nil ? "Nothing to run yet" : "Some services did not start",
            detail: """
                No start command found in: \(run.unstarted.joined(separator: ", ")).

                A service starts if it has a compose file, an npm dev/start script, Cargo.toml, \
                go.mod, or a Makefile dev target. Add `repos: [path, ...]` to the project's \
                frontmatter to point at the folders that do, or split a repo that holds more than \
                one app into `apps/` or `services/` subfolders so each is found on its own.
                """)
    }

    /// Asks for a title, then files the entry under what was selected when the user asked: the
    /// poll can move the selection while they type. `route` files it under something else — the
    /// milestone the Memory page's menu names.
    func add(_ kind: EntryKind, to project: ProjectModel, under route: Route? = nil) {
        let selection = route ?? self.selection
        alert = .title("New \(kind.displayName)") { [weak self] typed in
            let title = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, !title.isEmpty else { return }
            do {
                let destination = try project.add(kind, title: title, selection: selection)
                // Awaited, not the fire-and-forget poll: the new page has no card until the
                // notebook is read again, and `destination` is that card.
                Task {
                    await self.reloadNow()
                    self.go(to: destination)
                }
            } catch {
                self.alert = .error(error)
            }
        }
    }

    /// Asks before moving `card` to the Trash, and counts what goes with it from the board as it
    /// is now. The answer removes what was counted: the poll keeps running under the question,
    /// and a task an agent files meanwhile is left for the user to see.
    ///
    /// `trash` is for the tests, which delete rather than fill the user's Trash.
    func remove(_ card: NotebookCard, in project: ProjectModel, trash: Bool = true) {
        let cards = project.snapshot.cards
        let tasks = NotebookFormat.owned(by: card, in: cards).count - 1
        alert = .confirm(
            "Move \u{201C}\(card.title)\u{201D} to the Trash?",
            detail: card.kind == .project
                ? "The project folder, its memory and its \(tasks) task\(tasks == 1 ? "" : "s") go with it. "
                    + "You can put them back from the Trash."
                : "You can put it back from the Trash.",
            action: "Move to Trash"
        ) { [weak self] in
            guard let self else { return }
            do {
                if let route = try project.remove(card, from: cards, selection: self.selection, trash: trash) {
                    self.selection = route
                }
            } catch {
                self.alert = .error(error)
                return
            }
            self.reload()
        }
    }
}
