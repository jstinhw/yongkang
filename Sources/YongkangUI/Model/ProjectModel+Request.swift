import Foundation
import YongkangCore

/// One agent on a request, in whichever open project it runs, read as its sidebar row reads.
struct RequestAgent: Identifiable {
    let project: ProjectModel
    let row: AgentRow
    /// The Product of the project the request asked for its part: listed under the one that asked.
    let asked: Bool

    var id: String { row.id }

    /// Nil once the session has closed.
    @MainActor init?(on project: ProjectModel, session: UUID, asked: Bool, asking: [UUID: String]) {
        guard
            let row = project.value.agentRows(summary: project.summary, asking: asking).first(where: {
                $0.isRunningSession && $0.session?.id == session
            })
        else { return nil }
        self.project = project
        self.row = row
        self.asked = asked
    }
}

/// A request typed on the board, as it went to Product.
struct BoardRequest: Equatable {
    let session: UUID
    /// Every card on the board when it was sent. Whatever Product files is what is not in here.
    let before: Set<String>
    /// The project that asked, by folder, when its agent's message started this request rather
    /// than the board's own box. See `ProjectModel.receive`. Not kept across a relaunch.
    var from: URL? = nil
    /// The session there that asked: approving its request approves this one too. See
    /// `ProjectModel.askedRequests`. Not kept across a relaunch.
    var asker: UUID? = nil
    /// What Product last asked another project for this request, kept once the answer is in so
    /// the banner can say that project filed its part. Set by `ProjectModel.deliveries`; never on
    /// a request another project asked, where what Product writes back is its answer.
    var asked: Ask? = nil
    /// What was asked: the box's text, or the title of the message that started it. Names the
    /// request until Product has filed a milestone for it. Not kept across a relaunch.
    var prompt: String? = nil

    /// One message this request's Product sent: the project it went to, by folder, and its title.
    struct Ask: Equatable {
        let project: URL
        let title: String
    }
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
            request = BoardRequest(session: id, before: Set(cards.map(\.id)), prompt: text)
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

    /// What the request is called, wherever it is shown: the milestone Product filed for it, or
    /// until there is one, the first line of what was asked.
    var requestName: String? {
        guard let request else { return nil }
        let asked = request.prompt?.split(separator: "\n").first.map(String.init)
        return filed.first { $0.kind == .project }?.title ?? asked
    }

    /// Every agent on this project's request among the open projects, as its card lists them:
    /// the Product that asked, then the Product of the project it asked — the same two from
    /// either board. Only running sessions: one that has closed has left its part on its board.
    func requestAgents(among projects: [ProjectModel], asking: [UUID: String]) -> [RequestAgent] {
        guard let request else { return [] }
        // The request open in the project at `folder`, when it is the other half of this one.
        func half(in folder: URL?, asked: Bool, _ matches: (BoardRequest) -> Bool) -> RequestAgent? {
            guard let folder, let other = projects.first(where: { $0.isAt(folder) }), let theirs = other.request,
                matches(theirs)
            else { return nil }
            return RequestAgent(on: other, session: theirs.session, asked: asked, asking: asking)
        }
        let here = RequestAgent(on: self, session: request.session, asked: request.from != nil, asking: asking)
        if request.from != nil {
            let asker = half(in: request.from, asked: false) { $0.asked.map { self.isAt($0.project) } == true }
            return [asker, here].compactMap { $0 }
        }
        let asked = half(in: request.asked?.project, asked: true) { $0.from.map(self.isAt) == true }
        return [here, asked].compactMap { $0 }
    }

    /// Whether this project is the one in `folder`.
    func isAt(_ folder: URL) -> Bool { directory.standardizedFileURL.path == folder.standardizedFileURL.path }

    /// The box answers a request Product is still on, rather than starting a new one.
    var requestFollowsUp: Bool { requestSession != nil }

    /// Product's turn is over — or its session is gone — with a plan on disk not yet committed,
    /// which is the user's to approve or send back.
    var requestFinished: Bool { requestSettled && !planChanges.isEmpty }

    /// Product's turn is over — or its session is gone — and nothing it asked is still to come:
    /// a request another project's approval can take with it, even one that filed nothing.
    var requestSettled: Bool { request != nil && requestSession?.idle != false && requestWaitsOn == nil }

    /// The open requests this one asked other projects for, and those they asked in turn: what
    /// approving it approves too, so one click takes the whole plan. Found by the session that
    /// asked rather than by folder, so a request an earlier one left open there stays out of it.
    func askedRequests(among projects: [ProjectModel]) -> [ProjectModel] {
        var found: [ProjectModel] = []
        var askers = request.map { [$0.session] } ?? []
        while let asker = askers.popLast() {
            for other in projects where other !== self && !found.contains(where: { $0 === other }) {
                guard let theirs = other.request, theirs.asker == asker else { continue }
                found.append(other)
                askers.append(theirs.session)
            }
        }
        return found
    }

    /// The project the request's Product asked for its part and has not heard back from. Its plan
    /// is not finished until the answer is in: the tasks it files then depend on it.
    var requestWaitsOn: BoardRequest.Ask? {
        guard let request, let asked = request.asked, waitingOn[request.session] != nil else { return nil }
        return asked
    }

    /// The other project each session is talking to, as the sidebar and a session's header name
    /// it. Product answering the project that asked it is asked by that project, not waiting on
    /// it: what it wrote back was the answer.
    var peers: [UUID: Peer] {
        var peers = waitingOn.mapValues { Peer.waitingOn($0.lastPathComponent) }
        if let request, let from = request.from { peers[request.session] = .askedBy(from.lastPathComponent) }
        return peers
    }

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

    /// The Product session with nothing left to do: its turn is over and its plan is committed
    /// — by hand, since `Approve and commit` closes its own — which would leave it at "your
    /// turn" with no banner to close it from. Its plan is what its request filed or, once a
    /// relaunch has forgotten the request, its Page, which only a commit made by hand puts in
    /// git: the app never commits one.
    ///
    /// Only right after a read of the tree: one older than the notebook would call a plan
    /// Product has just written committed.
    func spentProduct() async -> CodeSession? {
        guard planChanges.isEmpty else { return nil }
        for session in sessions where session.isProduct && session.idle && !session.exited {
            if request?.session == session.id && !filed.isEmpty { return session }
            guard let drawn = NotebookFormat.drawnPage(of: session.id, in: notebookRoot) else { continue }
            let page = NotebookFormat.relativePath(drawn.url)
            if !repo.changes.contains(where: { $0.path == page }), await GitClient.committed(page, in: directory) {
                return session
            }
        }
        return nil
    }

    /// The Product session the last request went to, while it is still running.
    private var requestSession: CodeSession? {
        request.flatMap { request in sessions.first { $0.id == request.session && !$0.exited } }
    }
}
