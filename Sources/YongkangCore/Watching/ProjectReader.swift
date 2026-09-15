import Foundation

/// Everything one project is read from — its notebook, what its sessions have spawned and
/// spent, and what git says about its working tree — read off the main actor.
///
/// One per open project, so two projects read in parallel while one project's reads queue
/// behind each other. The reader never touches the window: it answers with values, and
/// `ProjectModel` is the only thing that publishes them. That is the whole split — the actor
/// reads, the model publishes, and a value that came back unchanged is never published at all.
///
/// Actors are reentrant, so a read suspended on git does not hold a notebook read behind it.
/// Answers can therefore still arrive in an order the reads did not start in, which is why
/// `ProjectModel` numbers its repo reads rather than trusting this queue.
package actor ProjectReader {
    package let directory: URL
    private var notebookRoot: URL { NotebookFormat.root(in: directory) }

    package init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Notebook

    /// The notebook read again, or nil when it says exactly what `previous` already does.
    /// Nil is what keeps a poll nobody wrote to from re-rendering every screen that reads it.
    ///
    /// See `NotebookSnapshot.reread` for what `frontmatter` and `records` add.
    package func notebook(
        after previous: NotebookSnapshot, frontmatter: Bool, records: Bool
    ) -> NotebookSnapshot? {
        let fresh = previous.reread(root: notebookRoot, frontmatter: frontmatter, records: records)
        return fresh == previous ? nil : fresh
    }

    // MARK: - Sessions

    /// What each of `project`'s agent sessions has spawned and recorded, plus the ledger write.
    ///
    /// `project` is the window's state as it was when the read started, and the answers are
    /// keyed by session id rather than by index: a session can be closed, or another added,
    /// while the providers read.
    package func sessions(of project: Project) async -> [SessionRead] {
        var reads: [SessionRead] = []
        // A service terminal has no provider, nothing to scan and nothing to spend.
        for session in project.sessions where session.agent != nil {
            var subagents: [SubagentStatus]?
            if !session.exited {
                // Each provider writes its subagents somewhere else — Claude Code beside the
                // parent session, Codex as sibling rollouts pointing back at it — so the
                // session's own agent reads them.
                subagents =
                    await session.agent?.provider
                    .subagents(session: session.id, project: directory, taskIDs: session.taskIDs)
                    // Named here rather than in either reader: the roster is project state, and
                    // the screens downstream should never each have to look a running agent up.
                    .map { $0.named(in: project.team) } ?? []
            }
            let handed = !session.taskIDs.isEmpty
            reads.append(
                SessionRead(
                    id: session.id, subagents: subagents,
                    coordination: handed ? await LeadCoordination.load(root: notebookRoot, session: session) : nil,
                    readRecords: handed))
        }
        // Written from the poll rather than from the usage screen: what an agent spent
        // has to survive a run in which nobody opened that screen, and the transcripts
        // it is read from are no longer findable once the sessions are gone.
        UsageLedger.record(await AgentUsage.spends(in: project), root: notebookRoot)
        return reads
    }

    // MARK: - Transcripts

    /// The lines of the one agent on screen. Reading and parsing a whole transcript is the
    /// most expensive thing the window asks for, so it happens here and arrives as a value.
    package func transcript(of provider: AgentProvider, at url: URL) -> [TranscriptLine] {
        provider.transcript(at: url)
    }

    // MARK: - Git

    /// What git says about the tree. `initializing` creates the repository when there is none:
    /// a project the agents work in needs one, because without it there is no diff to review
    /// and nowhere for an approval to commit. Created, never committed to.
    package func repo(after previous: RepoStatus, countingLines: Bool, initializing: Bool) async -> RepoStatus {
        if let status = await RepoStatus.read(in: directory, after: previous, countingLines: countingLines) {
            return status
        }
        guard initializing, await GitClient.initialize(in: directory) == nil else { return RepoStatus() }
        return await RepoStatus.read(in: directory, countingLines: countingLines) ?? RepoStatus()
    }
}

/// One session's answer from a poll. Every field is what the read found, not what the window
/// should show: the model compares each against what it holds and writes only the differences.
package struct SessionRead: Sendable {
    package let id: UUID
    /// What the session has spawned, or nil when it had already exited and nothing was scanned.
    package let subagents: [SubagentStatus]?
    /// The lead's plan as its run records now read. Nil means there are none.
    package let coordination: LeadCoordination?
    /// Whether the records were read at all. A session handed no tasks has none to read, and
    /// its coordination must be left as it is rather than cleared by a nil above.
    package let readRecords: Bool

    package init(
        id: UUID, subagents: [SubagentStatus]?, coordination: LeadCoordination?, readRecords: Bool
    ) {
        self.id = id
        self.subagents = subagents
        self.coordination = coordination
        self.readRecords = readRecords
    }
}
