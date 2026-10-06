import Foundation
import YongkangCore

/// A request typed on the board, as it went to Product.
struct BoardRequest: Equatable {
    let session: UUID
    /// Every card on the board when it was sent. Whatever Product files is what is not in here.
    let before: Set<String>
    /// The project that asked, by folder, when its agent's message started this request rather
    /// than the board's own box. See `ProjectModel.receive`. Not kept across a relaunch.
    var from: URL? = nil
}

extension ProjectModel {
    /// Hands what was typed in the board's request box to Product, which files it straight onto
    /// the board as milestones and tasks and decides what waits on what. Tags naming other
    /// projects go as paths the agent can open, and their folders are let in.
    ///
    /// The board stays on screen: the answer is the cards that turn up, so this goes nowhere.
    /// The `Destination` only carries what to type into a Product session already running —
    /// as a follow-up to the request it is on, or as a new request to one doing something else.
    func sendRequest(_ text: String, projects: [Mention.Project], agent: AgentKind) -> Destination {
        let (prompt, folders) = Mention.resolved(text, root: directory, projects: projects)
        let followUp = requestSession
        let sent =
            followUp.map { Destination(section: .board, route: .session($0.id), input: prompt) }
            ?? startProduct("describe\n" + prompt, agent: agent, reading: folders)
        if case .session(let id, _)? = sent.route, followUp == nil {
            request = BoardRequest(session: id, before: Set(cards.map(\.id)))
        }
        requestDraft = ""
        requestOpen = false
        return sent
    }

    /// The milestones and tasks Product has filed for the last request so far.
    var filed: [NotebookCard] {
        guard let request else { return [] }
        return cards.filter { ($0.kind == .project || $0.kind == .task) && !request.before.contains($0.id) }
    }

    /// The box answers a request Product is still on, rather than starting a new one.
    var requestFollowsUp: Bool { requestSession != nil }

    /// Product's turn is over — or its session is gone — with a plan on disk not yet committed,
    /// which is the user's to approve or send back.
    var requestFinished: Bool { request != nil && requestSession?.idle != false && !planChanges.isEmpty }

    /// The plan as git has it uncommitted: roadmap, milestone, task and memory files, less what
    /// a task handed to an agent commits from Review — its own file, and any memory it wrote.
    /// Read off disk rather than remembered, so it is still there after a relaunch.
    ///
    /// ponytail: a plan edit made by hand goes in with Product's. Remember the tree at send time,
    /// and keep it across launches, if those ever need to stay apart.
    var planChanges: [String] {
        let handed = Set(summary.tasks.flatMap(\.commitPaths))
        return repo.changes.map(\.path).filter { path in
            ["roadmap", "projects", "tasks"].contains { path.hasPrefix(".notebook/\($0)/") } && !handed.contains(path)
        }
    }

    /// The request a Product session is on, read back off disk: what its plan holds that is not
    /// committed is what it filed, and the banner waits on the user again. Run after a relaunch,
    /// and whenever Product's turn ends with no request open — one typed into its terminal, a
    /// review it wrote out, or a banner dismissed before it was approved — since Product points
    /// the user at `Approve and commit` however its turn began.
    func resumeRequest(of session: CodeSession) async {
        guard session.isProduct, request == nil else { return }
        // Product's last write may be newer than the last read of the tree.
        await refreshRepo(countingLines: false)
        let changed = Set(planChanges.map { directory.appendingPathComponent($0).standardizedFileURL.path })
        guard request == nil, !changed.isEmpty else { return }
        request = BoardRequest(
            session: session.id,
            before: Set(cards.filter { !changed.contains($0.url.standardizedFileURL.path) }.map(\.id)))
    }

    /// Approving a request commits what Product wrote for it and closes it: the banner and its
    /// "new" marks go. Nothing is assigned. Returns the Product session it ran in, if it is still
    /// open, for the caller to close — its work is on the board and in the commit.
    func approveRequest() async throws(CommitFailure) -> CodeSession? {
        guard let request else { return nil }
        // Product's last write may be newer than the last read of the tree.
        await refreshRepo()
        let paths = planChanges
        if !paths.isEmpty {
            let title = filed.first { $0.kind == .project }?.title ?? filed.first?.title ?? "the request"
            let failure = await GitClient.commit(message: "Plan \(title)", paths: paths, in: directory)
            await refreshRepo()
            if let failure { throw CommitFailure(reason: failure) }
        }
        Analytics.capture("request_approved", ["files": paths.count])
        self.request = nil
        return sessions.first { $0.id == request.session && !$0.exited }
    }

    /// The Product session the last request went to, while it is still running.
    private var requestSession: CodeSession? {
        request.flatMap { request in sessions.first { $0.id == request.session && !$0.exited } }
    }
}
