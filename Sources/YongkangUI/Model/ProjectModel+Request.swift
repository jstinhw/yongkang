import Foundation
import YongkangCore

/// A request typed on the board, as it went to Product.
struct BoardRequest: Equatable {
    let session: UUID
    /// Every card on the board when it was sent. Whatever Product files is what is not in here.
    let before: Set<String>
    /// Every file already changed when it was sent. Approving commits none of these: they were
    /// someone else's before Product started.
    let dirty: Set<String>
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
            request = BoardRequest(
                session: id, before: Set(cards.map(\.id)), dirty: Set(repo.changes.map(\.path)))
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

    /// Product has filed something and its turn is over — or its session is gone — so what it
    /// filed is the user's to approve or send back.
    var requestFinished: Bool { !filed.isEmpty && requestSession?.idle != false }

    /// What approving the request commits: the plan files changed since it was sent, less the
    /// task files a running agent holds, which are that agent's work for Review.
    ///
    /// ponytail: a file already changed when the request went out is left out even if Product
    /// edited it too, and stays for All changes. Snapshot its contents at send time if that bites.
    var requestPaths: [String] {
        guard let request else { return [] }
        let held = Set(
            cards.filter { card in sessions.contains { !$0.exited && $0.taskIDs.contains(card.id) } }
                .map(\.url.standardizedFileURL.path))
        return repo.changes.map(\.path).filter { path in
            ["roadmap", "projects", "tasks"].contains { path.hasPrefix(".notebook/\($0)/") }
                && !request.dirty.contains(path)
                && !held.contains(directory.appendingPathComponent(path).standardizedFileURL.path)
        }
    }

    /// Approving a request commits what Product wrote for it and closes it: the banner and its
    /// "new" marks go. Nothing is assigned. Returns the Product session it ran in, if it is still
    /// open, for the caller to close — its work is on the board and in the commit.
    func approveRequest() async throws(CommitFailure) -> CodeSession? {
        guard let request else { return nil }
        // Product's last write may be newer than the last read of the tree.
        await refreshRepo()
        let paths = requestPaths
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
