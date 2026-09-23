import Foundation

extension NotebookFormat {
    /// Where a session's page lives: what it drew for the user, shown on its Page tab. Like
    /// `blocks/`, `pages/` is a channel to the app rather than notebook content, so the spec
    /// does not list it; the prompts that ask for a page say where it goes.
    package static func page(of sessionID: UUID, in notebookRoot: URL) -> URL {
        notebookRoot.appendingPathComponent(pagePath(sessionID))
    }

    private static func pagePath(_ sessionID: UUID) -> String { "pages/\(sessionID.uuidString.lowercased()).html" }

    /// Where anything the user has to look at goes: one file per session, in the app. An
    /// artifact or a file the agent opened put a browser tab in front of the window every
    /// time, and a file path in a terminal is something the user has to go and open.
    private static func page(_ sessionID: UUID) -> String {
        "one HTML file at `\(folderName)/\(pagePath(sessionID))`, which I see on this session's Page tab "
            + "in the app. Rewrite that file each time, and never publish an artifact or open a browser for it"
    }

    /// How every plan reaches the user's eyes — a new notebook, a described feature, a
    /// review's next move — so setup and Product draw the same map. A graph, not the draft's
    /// lists, because the dependencies are what the user reviews; Mermaid, because any agent
    /// writes it and it lays the arrows out itself.
    private static func planGraph(_ sessionID: UUID) -> String {
        """
        Whenever a plan with projects and tasks is ready for me under Blocks, and each time it
        changes, show it to me as a graph: \(page(sessionID)). Never ask me to open files.

        Draw it with Mermaid from cdn.jsdelivr.net/npm as a `flowchart LR`: a subgraph per
        roadmap entry holding its projects, a subgraph per project holding its tasks, each task
        a node with its id and a few words on what it changes, and an arrow from every
        `depends_on` to what waits on it, between projects as well as tasks. Style design tasks
        apart, outline the tasks that can start at once, fade what already exists that the plan
        only builds on, and add a one-line legend. It maps the plan, not the product: no
        mockups.
        """
    }

    /// Opens the session an empty project starts with, seeded by what the user typed.
    /// It carries the spec inline rather than pointing at NOTEBOOK.md, because the
    /// point of an empty project is that nothing has been written to it yet — the
    /// agent writes the first file.
    ///
    /// The plan is drafted as a ready proposal before any of it is written, so the user
    /// knows what they are getting while changing it is still cheap. The session id goes
    /// in the draft so `Create project` on it comes back to this conversation.
    ///
    /// The draft is marked done last because that is what ends the session (see
    /// `ProjectModel.finishedSetups`): once it flips, only the agent's summary is left.
    package static func onboardingPrompt(description: String, sessionID: UUID) -> String {
        """
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

    private static func taskList(_ tasks: [NotebookCard]) -> String {
        tasks.map { task in
            var lines = ["Task id: \(task.id)", "Task file: \(relativePath(task.url))"]
            if let project = task.project { lines.append("Project: \(project)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// What an agent handed other folders is told about them: read, never change — Review only
    /// sees, and only commits, the project it works in. Empty when it was handed none.
    package static func readingNote(_ reading: [String]) -> String {
        guard !reading.isEmpty else { return "" }
        return "\nYou may also read " + reading.map { "`\($0)`" }.joined(separator: ", ")
            + " for reference. Change nothing there: only this project's changes are reviewed and committed.\n"
    }

    /// What an assigned session is told: its chain of tasks, and the few things the app reads
    /// back — status, a report per task, blocks, no commits. How to do the work is left to the
    /// agent. Work that could run beside this chain is another session's, not this one's.
    ///
    /// The session id goes in so a block or demo says who is waiting on it, and so a report
    /// is filed under the session that wrote it. The report's shape is what Review reads:
    /// `paths` is what lets approving one task commit only its files.
    ///
    /// `reading` is the other folders the session was given, which it may read and must not change:
    /// Review only sees, and only commits, this project's changes.
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
        let others = readingNote(reading)
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
            you have checked every item of its Done when.
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

            When you stop — all done, or waiting on me — show me the report as a page: \(page(sessionID)).
            One section per task: its status, what changed, how you checked it, the files, the
            calls you made, and what is left. Put what needs me first.
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
    package static func productPrompt(arguments: String, sessionID: UUID, agent: AgentKind) -> String {
        agent.skill("product", arguments: arguments + "\nSession id: \(sessionID.uuidString.lowercased())")
            + "\n\n" + planGraph(sessionID)
    }

    /// The session that clears one block with the user. The file carries what is needed and
    /// the steps; the way back is setting `status: done` in it, which the app reads and
    /// types into the session waiting behind it. A proposal never comes here: it goes back to
    /// its Product transcript, or to a new Product session once that has exited.
    package static func unblockPrompt(block: UserBlock) -> String {
        """
        Help me clear the block in `\(relativePath(block.url))`. Do every step that does not need \
        me first. Then say in a few lines what it unblocks, and take the rest one step at a \
        time: open the page for that step yourself, give one instruction, wait, and verify it \
        before the next. Never echo a secret I paste or write one anywhere the repo tracks. \
        When it is done, set the block's `status: done` with a one-line `resolution`.
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
