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
    /// Never changes, so anyone may ask without waiting for the reads in front of them.
    nonisolated package let directory: URL
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

    // MARK: - Watching

    /// The folders this project's state can change in, and the fingerprint of what the usage
    /// screen reads. Both are answers about the same handful of per-session files, so they are
    /// found in one pass here rather than by two callers asking each provider separately.
    ///
    /// ponytail: each session's file is resolved once here and once more inside
    /// `AgentUsage.spends`, which doesn't hand back the URLs it used. Two lookups per live
    /// session per read, and for Codex a lookup is a walk of `~/.codex/sessions`. Make `spends`
    /// return its sources if that ever shows up in a trace.
    package func watch(of project: Project) async -> ProjectWatch {
        var folders = [directory]
        var sizes: [Int] = []
        for session in project.sessions {
            guard let url = await session.agent?.provider.usageURL(session: session.id, project: directory)
            else { continue }
            // Only a live session's folder: a finished agent's transcript is never written
            // again, and its spend is in the ledger by now.
            if !session.exited { folders.append(url.deletingLastPathComponent()) }
            sizes.append(Self.size(of: url))
        }
        let rows = project.sessions.map { session in
            session.id.uuidString + session.subagents.map { $0.id + "\($0.running)" }.joined()
        }
        return ProjectWatch(
            folders: folders,
            usage: rows.joined()
                + "\(project.sessions.count):\(Self.size(of: UsageLedger.url(root: notebookRoot))):\(sizes)")
    }

    /// A file's size, or 0 when it isn't there yet. One `stat`, no read: a byte more in a
    /// transcript is a token more, which is all the usage screen needs to know.
    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    // MARK: - Transcripts

    /// The lines of the one agent on screen. Reading and parsing a whole transcript is the
    /// most expensive thing the window asks for, so it happens here and arrives as a value.
    package func transcript(of provider: any AgentProvider, at url: URL) -> [TranscriptLine] {
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

/// What one project has to watch, and what the usage screen has to notice. See
/// `ProjectReader.watch(of:)`.
package struct ProjectWatch: Equatable, Sendable {
    /// What `FSEventWatcher` is handed: the project's own tree, which holds `.notebook/` and
    /// everything git diffs, and each live session's transcript folder, which its CLI keeps
    /// under its own home rather than in the project.
    package let folders: [URL]
    /// The sessions and subagents the usage screen draws rows for, and the sizes of the files
    /// it reads their spend from. Published only when it differs, which is exactly when that
    /// screen has something new to show.
    package let usage: String

    package init(folders: [URL], usage: String) {
        self.folders = folders
        self.usage = usage
    }
}

/// One session's answer from a poll. Every field is what the read found, not what the window
/// should show: the model compares each against what it holds and writes only the differences.
package struct SessionRead: Sendable {
    package let id: UUID
    /// What the session has spawned, or nil when it had already exited and nothing was scanned.
    package let subagents: [SubagentStatus]?
    /// The session's reports as its run records now read. Nil means there are none.
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
