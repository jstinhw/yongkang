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
    /// A title to type. `create` gets what was typed when the user picks `action`.
    case title(String, action: String = "Create", create: @MainActor @Sendable (String) -> Void)

    static func error(_ error: any Error) -> AlertItem {
        let error = error as NSError
        return .message(error.localizedDescription, detail: error.localizedRecoverySuggestion ?? "")
    }

    var title: String {
        switch self {
        case .message(let title, _), .confirm(let title, _, _, _), .title(let title, _, _): return title
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
    /// Brings back, at launch, each waiting demo whose page a quit took down — only those
    /// whose command the user already let run. Anything else waits until its demo is opened,
    /// so a launch never opens on a pile of questions.
    func serveDemos() async {
        for project in projects {
            for block in project.snapshot.blocks where block.isDemo && block.waiting {
                guard let down = await project.downDemo(block), project.trustsServe(down.command) else { continue }
                project.startServing(block)
            }
        }
    }

    /// Opening a demo whose page is down: runs its command, asking first when this project has
    /// not run that exact command before, and shows the exact command in the question. True once
    /// the page answers; after a question, the panes are reloaded when the server is up.
    func serve(_ block: UserBlock, in project: ProjectModel) async -> Bool {
        guard let down = await project.downDemo(block) else { return false }
        guard project.trustsServe(down.command) else {
            alert = .confirm(
                "Serve this demo?",
                detail: "Its page is not running. This runs, in \(project.name):\n\n\(down.command)",
                action: "Run"
            ) {
                project.trustServe(down.command)
                project.startServing(block)
                Task { if await DemoServer.waitUntilAnswering(down.url) { DemoPages.reload(down.url) } }
            }
            return false
        }
        project.startServing(block)
        return await DemoServer.waitUntilAnswering(down.url)
    }

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

    /// Asks before throwing a task's finished work away: unlike the Trash, a new file git has
    /// never seen does not come back. Yes reverts it and sets the task back to `todo`, where it
    /// waits on the board to be assigned.
    func discard(_ task: SummaryTask, in project: ProjectModel) {
        let count = task.discardPaths.count
        let shared = task.files.filter { project.summary.sharing($0.path, besides: task) != nil }.count
        alert = .confirm(
            "Discard \u{201C}\(task.title)\u{201D}?",
            detail: (count == 0
                ? "It has no changed files. "
                : "Its \(count) changed file\(count == 1 ? "" : "s") go back to the last commit, and the "
                    + "new ones are deleted. This can't be undone. ")
                + (shared == 0 ? "" : "\(shared) of them also hold another task's edits, which go too. ")
                + (project.blockedTaskIDs.contains(task.id) ? "Its open demo or block is closed. " : "")
                + (project.assignedTaskIDs.contains(task.id)
                    ? "The task goes back to todo; close the session holding it to assign it again."
                    : "The task goes back to todo, ready to assign again."),
            action: "Discard"
        ) { [weak self] in
            Task {
                guard let self else { return }
                do throws(CommitFailure) {
                    try await project.discard(task)
                } catch {
                    self.alert = .message("The work was not discarded", detail: error.reason)
                }
            }
        }
    }

    /// Approving what Product filed for a request: commits it, then closes the request and the
    /// Product session it ran in — and the same on every project it asked for a part, each
    /// committing its own. Like a task's approval it asks nothing first; only a refusal from
    /// git is said, and a part whose Product is still working, which is left on its own board.
    func approveRequest(in project: ProjectModel) {
        let asked = project.askedRequests(among: projects)
        let working = asked.filter { !$0.requestSettled }
        Task {
            for each in [project] + asked.filter(\.requestSettled) {
                do throws(CommitFailure) {
                    if let session = try await each.approveRequest() { close(session, in: each) }
                } catch {
                    let title = each === project ? "The request" : "\(each.name)\u{2019}s part"
                    alert = .message("\(title) was not committed", detail: error.reason)
                    return
                }
            }
            guard !working.isEmpty else { return }
            let names = working.map(\.name).joined(separator: ", ")
            alert = .message(
                "Not every part was approved",
                detail: "Product is still working in \(names). Approve its part on its own board once it stops.")
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
