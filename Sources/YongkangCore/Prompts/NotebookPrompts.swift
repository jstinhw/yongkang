import Foundation

extension NotebookFormat {
    /// Where a session's HTML page lives, shown on its Page tab. No prompt asks for one now —
    /// a work session's report is its run records' `## Review`, which the app draws — but a
    /// session that wrote one before keeps it. Like `blocks/`, `pages/` is a channel to the app
    /// rather than notebook content, so the spec does not list it.
    package static func page(of sessionID: UUID, in notebookRoot: URL) -> URL {
        notebookRoot.appendingPathComponent(pagePath(sessionID))
    }

    private static func pagePath(_ sessionID: UUID) -> String { "pages/\(sessionID.uuidString.lowercased()).html" }

    /// Where a session's plan lives: the data setup and Product hand over, which the app draws
    /// on the same Page tab (`PlanDrawing`). Beside the page rather than inside it, so a
    /// session that drew one never has to know about the other.
    package static func plan(of sessionID: UUID, in notebookRoot: URL) -> URL {
        notebookRoot.appendingPathComponent(planPath(sessionID))
    }

    private static func planPath(_ sessionID: UUID) -> String { "pages/\(sessionID.uuidString.lowercased()).json" }

    /// What the session's Page tab shows: whichever of its plan and its page it wrote last,
    /// with that file's date, or nil before it has written either.
    package static func drawnPage(of sessionID: UUID, in notebookRoot: URL) -> (url: URL, modified: Date)? {
        [plan(of: sessionID, in: notebookRoot), page(of: sessionID, in: notebookRoot)]
            .compactMap { url in
                ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)
                    .map { (url: url, modified: $0) }
            }
            .max { $0.modified < $1.modified }
    }

    /// How every plan reaches the user's eyes — a new notebook, a described feature, a
    /// review's next move — so setup and Product show the same page. A graph, not the draft's
    /// lists, because the dependencies are what the user reviews.
    ///
    /// The agent hands over the plan as data and the app draws it (`PlanDrawing`). When each
    /// agent drew its own page, each picked its own colours, a faded box could come out grey on
    /// grey, and a plan was only as readable as the agent that drew it.
    ///
    /// The two lists carry what a graph cannot: why the plan is worth approving, and the
    /// moments it stops without the user. The word limits are the point — the page is read in
    /// seconds, and the detail stays in the draft, the wall of text it exists to replace.
    private static func planGraph(_ sessionID: UUID) -> String {
        """
        Whenever a plan with projects and tasks is ready for me under Blocks, and each time it
        changes, show it to me: write it as JSON to `\(folderName)/\(planPath(sessionID))`, which
        the app draws on this session's Page tab. Rewrite that file each time. Never draw a page
        for it yourself, publish an artifact, open a browser or ask me to open files.

            {
              "title": "<the plan, in two to four words>",
              "outcomes": ["<what someone can do once it lands, seven words at most>"],
              "needs_you": [{"task": "<task id>", "action": "<what I do, six words at most>"}],
              "tasks": [{"id": "<task id>", "title": "<what it changes, five words at most>",
                         "project": "<its project id>", "depends_on": ["<id>"],
                         "design": <true for design work>, "detail": "<twelve words at most>"}],
              "outside": [{"id": "<id>", "title": "<five words at most>",
                           "where": "<its project, or the other project's folder>",
                           "done": <false while it does not exist yet>}]
            }

        Four outcomes at most. `needs_you` is every moment the plan waits on me — an approval, an
        account, a secret, a DNS change. `tasks` is every task the plan builds; `outside` is
        everything they depend on that it does not: what already exists, and what another
        project's board delivers. `depends_on` names ids from either list. Plain words, no
        Markdown. The app works out the layout and what can start at once.
        """
    }

    /// Opens the session a project without a notebook starts with, seeded by what the user
    /// typed or, with no description, by the folder's own contents (`importPrompt`). It carries
    /// the spec inline rather than pointing at NOTEBOOK.md, because nothing has been written to
    /// the notebook yet — the agent writes the first file.
    ///
    /// A described project's plan is drafted as a ready proposal before any of it is written, so the user
    /// knows what they are getting while changing it is still cheap. The session id goes
    /// in the draft so `Create project` on it comes back to this conversation.
    ///
    /// The draft is marked done last because that is what ends the session (see
    /// `ProjectModel.finishedSetups`): once it flips, only the agent's summary is left.
    package static func onboardingPrompt(description: String?, sessionID: UUID) -> String {
        guard let description else { return importPrompt }
        return """
            This project has no notebook yet. Help me start one. What I want to build:

            \(description)

            First ask what is missing or ambiguous, one question at a time, each with two to
            four numbered options and your recommendation first, so I can answer with one
            character. Write nothing to this folder while we talk, and design nothing: how
            something looks is settled later, by a design task in the plan.

            Then write the format below verbatim to `\(folderName)/\(specFile)`, and draft the
            plan as `\(folderName)/blocks/plan.md` with this frontmatter:

                ---
                id: plan
                kind: proposal
                title: "Plan for <the product, in two or three words>"
                status: open
                stage: ready
                session: \(sessionID.uuidString.lowercased())
                action: "Return to the setup session to change the plan."
                created: YYYY-MM-DD
                updated: YYYY-MM-DD
                ---

            The draft, in this order:

            - What I will have once every task lands: what someone can do, not how it is built.
            - The roadmap entries and their projects, each with its outcome, `depends_on` and
              `repos`.
            - Every task, grouped by project in build order: its id, the change I could see or
              check, its `depends_on`, its `designer` if it is design work, and its Done when.
            - Which tasks can start together.
            - The calls you made where I was vague, and what is left out.

            Each task goes to its own agent, which sees only that task's file and the files it
            depends on. So a task is the smallest change that can be checked on its own;
            `depends_on` names only what it uses, and its Context says what it takes from each;
            tasks with no dependency between them never change the same screen, endpoint or
            module. A screen, layout or visual style to settle is its own task with
            `designer: Allen`, and the tasks that build it depend on it.

            Tell me the draft is under Blocks and wait. Change only the draft when I ask, and say
            what moved.

            \(planGraph(sessionID))

            Once I approve, with `Create project` or in my own words, write the roadmap, project
            and task files and one memory entry per call you made in the project it affects, and
            append one run record for this session with the primary roadmap id as `subject`.
            Then, as your last write, set the draft's `status: done` with
            `resolution: "Wrote the notebook."`, and tell me in a few lines what you created.
            That ends this session: the app closes it once you have said it, so ask me nothing
            after it.

            Everything goes in `\(folderName)/`; leave the rest of this folder untouched.

            The format:

            \(specText)
            """
    }

    /// A folder that already holds a project answers "what is it for" itself, so the agent reads
    /// rather than asks, and writes only what the notebook needs to stand up: its format, a run
    /// record and the roadmap. Milestones and tasks are Product's to plan from that roadmap, so
    /// there is no plan to approve and the import is over as soon as the code is understood.
    ///
    /// The roadmap is the last write because its folder appearing is what makes the project read
    /// as having a notebook, which is what ends the session (see `ProjectModel.finishedSetups`).
    private static let importPrompt = """
        This folder already holds a project, but it has no notebook yet. Start one for it: the
        roadmap only. Milestones and tasks come later, planned by Product from that roadmap.

        First read the whole project: the README and docs, the code, its config and build
        files, the tests and the git history. Work out what it is, who it is for, what it
        already does and where it is heading. Ask me nothing — the project answers that — and
        where reading leaves a choice open, make the call and say so in the roadmap's Context.
        Design nothing.

        Then write, in this order:

        1. The format below, verbatim, to `\(folderName)/\(specFile)`.
        2. One run record for this session in `\(folderName)/runs/`, with the roadmap's id as
           `subject`.
        3. As your last write, one roadmap entry in `\(folderName)/roadmap/`: the goal, what
           success looks like, the context an agent needs before changing this code, and what
           it is not doing. No milestones, tasks or memory: leave its Projects section out.

        Then tell me in a few lines what you wrote. That ends this session: the app closes it
        once you have said it, so ask me nothing after it.

        Everything goes in `\(folderName)/`; leave the rest of this folder untouched.

        The format:

        \(specText)
        """

    private static func taskList(_ tasks: [NotebookCard]) -> String {
        tasks.map { task in
            var lines = ["Task id: \(task.id)", "Task file: \(relativePath(task.url))"]
            if let project = task.project { lines.append("Project: \(project)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// What an agent handed other folders is told about them: read, never change — Review only
    /// sees, and only commits, the project it works in. A change one of them needs is asked
    /// of it instead, as a message in this notebook that the app types into that project's
    /// Product, so the change lands through that project's own board and Review. Empty when
    /// it was handed none.
    ///
    /// The message goes first and whole so the two projects plan at once, the other never
    /// reading a plan here that is half written. The turn that ends before the answer ends in
    /// one line: a summary then is one the answer would change, and reads as the user's move.
    ///
    /// `reading` is each folder relative to this project's, which is what `to` names.
    package static func readingNote(_ reading: [String], sessionID: UUID) -> String {
        guard !reading.isEmpty else { return "" }
        return """

            You may also read \(reading.map { "`\($0)`" }.joined(separator: ", ")) for reference. \
            Change nothing there: only this project's changes are reviewed and committed. When one \
            of them needs a change, ask it: write `\(folderName)/messages/<slug>.md` in this \
            project, never in theirs:

                ---
                kind: message
                to: "<that folder, as written above>"
                session: \(sessionID.uuidString.lowercased())
                reply_to: ""
                title: "<a few words>"
                created: <RFC-3339>
                ---

                What you need from it and why, in plain words.

            The app types it into that project's Product, which files the change on its own board \
            and answers into this session. Write it as soon as you know what you need, before the \
            rest of your work, so that project works while you do, and put in it everything it \
            needs to answer without reading this project. Carry on with what does not need the \
            answer, then end your turn in one line naming what you are waiting on: your summary \
            waits for the answer, which is typed in here.

            """
    }

    /// A message from another project's agent, as the app types it into the session it goes
    /// to: the receiving project's Product for a first message, as `asked` — "asked\n" followed
    /// by this — or, for a reply, the session its `reply_to` names, as it is. The answer comes
    /// filled in, so the receiver looks nothing up to reach the session that asked.
    ///
    /// `folder` is the sender's folder relative to the receiver's; `session`, the sender's id.
    package static func incomingMessage(from folder: String, session: String, title: String, body: String) -> String {
        """
        A message from the project in `\(folder)`, session \(session): "\(title)"

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))

        Change nothing in `\(folder)`. Answer by writing `\(folderName)/messages/<slug>.md` in \
        this project, never in theirs:

            ---
            kind: message
            to: "\(folder)"
            session: <your session id>
            reply_to: \(session)
            title: "<a few words>"
            created: <RFC-3339>
            ---

            Your answer, in plain words.

        The app types it into the session that asked.
        """
    }

    /// What the session that wrote `file` is told when its `to` names no project open here: one
    /// line, so it can say so to the user and carry on.
    package static func undeliveredMessage(to folder: String, file: String) -> String {
        "Not delivered: no project open in Yongkang is at `\(folder)`, so nobody read \(file). "
            + "Ask the user to open that project, or carry on without its answer."
    }

    /// What an assigned session is told: its chain of tasks, and the few things the app reads
    /// back — status, a report per task, blocks, no commits. How to do the work is left to the
    /// agent. Work that could run beside this chain is another session's, not this one's.
    ///
    /// The session id goes in so a block or demo says who is waiting on it, and so a report
    /// is filed under the session that wrote it. The report's shape is what Review reads:
    /// `paths` is what lets approving one task commit only its files.
    ///
    /// `reading` is the other folders the session was given, relative to this project's, which
    /// it may read and must not change: Review only sees, and only commits, this project's
    /// changes. A change there it asks for — see `readingNote`.
    package static func workPrompt(
        tasks: [NotebookCard], sessionID: UUID, message: String = "", reading: [String] = []
    ) -> String {
        let id = sessionID.uuidString.lowercased()
        let designer =
            BundledSkills.url("designer").map { "the designer skill at `\($0.path)`" } ?? "the `designer` skill"
        let design =
            tasks.contains(where: \.isDesignWork)
            ? "\nA task with `designer:` set is design work: follow \(designer) for it, and start "
                + "nothing that depends on it until I approve its demo.\n"
            : ""
        let asked = message.isEmpty ? "" : "\n\(message)\n"
        let others = readingNote(reading, sessionID: sessionID)
        // One task has no order to keep and nothing to run beside it, and every line an
        // agent is handed is one it tries to act on.
        let chain =
            tasks.count > 1
            ? " Several tasks here are one chain: go in `depends_on` order, and only run two at "
                + "once — with your own subagents, one writer per file, each named after its task "
                + "id — where neither waits on the other."
            : ""
        return """
            Build \(tasks.count == 1 ? "this task" : "these tasks") from the notebook in `\(folderName)/`.

            \(taskList(tasks))
            Session id: \(id)
            \(asked)\(others)
            Read each task file, what it depends on and its project's memory; the Done when list
            is the contract.\(chain) Set a task `status: active` when you start it and `done` once
            you have checked every item of its Done when. A check that fails is yours to fix
            before `done`, even one your change did not cause, like a flaky test: work it shows
            failing is not ready for my review.
            \(design)
            When only I can unblock something — an account, a secret, a payment — write
            `\(folderName)/blocks/<slug>.md` with `kind: block`, `status: open`, `session: \(id)`,
            `task`, `title`, `url`, `action`, `created` and `updated`, then `## Needed from you` and
            the `## Steps` to get there. Carry on with the rest until I say it is unblocked.

            Never stage, commit, push, stash or switch branches: I review each task and commit it.

            Report each task in `\(folderName)/runs/\(id)-work-<work id>.md`, where the work id is
            the task id, with `-2`, `-3` for a later attempt at it:

                ---
                kind: run
                session: \(id)
                task: <task id>
                work_id: <work id>
                title: "<what you did, in a few words>"
                status: running | blocked | done | failed
                paths: [<every file you changed, repo-relative>]
                report: "<one line>"
                started_at: <RFC-3339>
                finished_at: <RFC-3339>
                ---

                ## Result
                What changed that I can see or check.

                ## Verification
                The commands you ran and what they printed.

                ## Review
                ```json
                {
                  "summary": "<what changed, one sentence of 25 words at most>",
                  "confidence": "high | medium | low",
                  "confidence_why": "<why, 15 words at most>",
                  "touches": "<what it touches, four words at most>",
                  "changed": ["<an outcome I can see or check, 15 words at most>"],
                  "checks": [{"claim": "<what it proves, five words at most>",
                              "status": "passed | failed | not_run",
                              "result": "<what it printed, ten words at most>",
                              "command": "<the command and its output>"}],
                  "holds": ["<what keeps it safe whatever the code does, 20 words at most>"],
                  "spots": [{"path": "<repo-relative file>", "lines": [<first>, <last>],
                             "label": "<where, two words>", "why": "<why I read it, 25 words at most>"}],
                  "questions": [{"ask": "<what only I can decide>", "context": "<20 words at most>",
                                 "options": ["<three words at most>"], "recommend": <its index>}],
                  "concerns": [{"title": "<six words at most>", "detail": "<25 words at most>",
                                "blocks": <true if I should not approve until it is settled>}],
                  "outside": [{"kind": "read | local | write", "what": "<what you did outside this repo>"}],
                  "files": [{"path": "<a file in paths>", "why": "<eight words at most>"}],
                  "next": "<what landing this unblocks, 12 words at most>"
                }
                ```

            The Review is what the app shows me when you stop, and I read it in seconds: keep to the
            word limits, plain words, and leave the detail to Result and Verification. Every check
            you ran goes in `checks`, and one you could not run is `not_run`, never left out.
            `spots` are the few places a person should read because no check covers them, with
            line numbers in the file as it is now. `outside` is every call that left this repo — a
            network read, a download, a write anywhere — and empty when there was none. Ask in
            `questions` only what you cannot decide; my answer comes back to you here. Rewrite the
            record whenever any of it changes. Never draw a page, publish an artifact or open a
            browser for it.
            """
    }

    /// What the user says about a demo, on its way to the designer. A demo that comes back
    /// is the next pass on the one already built, never the task again from the top: the
    /// file it names carries the revisions so far, and the answer joins them.
    package static func demoChangeRequest(demo: UserBlock, note: String) -> String {
        let said = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
            Changes requested on the demo \(demo.slug) — "\(demo.title)".

            \(said)

            This is the next pass on that demo, not the task again: read \
            `\(relativePath(demo.url))` for where it got to, change what I asked and leave \
            the rest alone, serve it, and append a `## Revisions` line saying what moved. \
            Do not commit.
            """
    }

    /// Product writes its session id into the Blocks notification, making that row a link
    /// back to the transcript where the proposal is discussed. Every way into Product — a
    /// review, a described feature, a proposal reopened from Blocks — comes through here, so
    /// each shows its plan as the same graph setup does.
    ///
    /// `reading` is the other projects a request tagged, relative to this one: Product reads
    /// them and asks them, as an assigned session does.
    package static func productPrompt(
        arguments: String, sessionID: UUID, agent: AgentKind, reading: [String] = []
    ) -> String {
        agent.skill(
            "product",
            arguments: arguments + "\nSession id: \(sessionID.uuidString.lowercased())"
                + readingNote(reading, sessionID: sessionID))
            + "\n\n" + planGraph(sessionID)
    }

    /// The session that clears one block with the user. The file carries what is needed and
    /// the steps; the way back is setting `status: done` in it, which the app reads and
    /// types into the session waiting behind it. A proposal never comes here: it goes back to
    /// its Product transcript, or to a new Product session once that has exited.
    /// A step the agent can check is polled rather than confirmed by the user. The poll is
    /// bounded because whatever the user types while it runs queues behind it.
    package static func unblockPrompt(block: UserBlock) -> String {
        """
        Clear the block in `\(relativePath(block.url))`. Work through it yourself first: check \
        what already exists and do every step that does not need me. Most of them turn out not \
        to. If nothing is left for me, set `status: done` with a one-line `resolution` and say \
        so in one line.

        Only when something is genuinely mine — a credential, a consent screen, an account — \
        come back to me. Say in two or three lines what is being set up and what it unblocks, \
        then take it one step at a time: one instruction, one or two lines. When a step leaves \
        something you can check from here — a repo gone, a secret set, a CLI signed in — do \
        not ask me to say it is done: poll for it every few seconds, for a few minutes at most, \
        and go on to the next step the moment it shows. Check for the outcome itself, so an \
        error does not read as done. Wait for my answer only when there is nothing to check, or \
        the polling runs out. Never paste, summarise or list the steps from the block file — \
        they are written for you, not for me.

        Signing in, consenting and choosing are mine. Fetching is not. The moment I have \
        signed in or authorised something, go and read what you need yourself — the CLI I just \
        authenticated, a file on this Mac, the keychain, an API the account now allows — \
        instead of telling me to find a value on a page and copy it out. Reorder the block's \
        steps when that turns a question for me into a command for you, and do the step that \
        makes the value readable first. Ask me to copy something only after you have looked \
        and there is genuinely no other way, and say that you looked.

        I am looking at a browser pane beside this session showing the block's `url:`. It is \
        how you open a page: set `url:` in the block file to the page the current step needs, \
        as the step comes up, and it is in front of me. Do not print a link for me to click.

        Never echo a secret I paste or write one anywhere the repo tracks. When it is done, set \
        `status: done` with a one-line `resolution`.
        """
    }

    /// Incubate mode's opening prompt: the description of an agent that does not exist
    /// yet. The skill owns how to search for a skill to give it and what to write; the
    /// prompt carries only what the user typed.
    package static func incubatePrompt(brief: String, agent: AgentKind) -> String {
        agent.skill("incubate-agent", arguments: brief)
    }

    /// Typed into the waiting session once its block clears — the same words a person
    /// would use coming back to say the account is set up now.
    package static func unblockedMessage(block: UserBlock) -> String {
        let detail = block.resolution.isEmpty ? "" : " \(block.resolution)"
        return "Unblocked: \(block.title).\(detail) Continue from where you stopped."
    }
}
