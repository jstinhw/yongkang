import Foundation

extension NotebookFormat {
    /// Opens the session an empty project starts with, seeded by what the user typed.
    /// It carries the spec inline rather than pointing at NOTEBOOK.md, because the
    /// point of an empty project is that nothing has been written to it yet — the
    /// agent writes the first file.
    ///
    /// The plan is drafted as a ready proposal before any of it is written, so the user
    /// knows what they are getting while changing it is still cheap. The session id goes
    /// in the draft so `Create project` on it comes back to this conversation.
    package static func onboardingPrompt(description: String, sessionID: UUID) -> String {
        """
        This project has no notebook yet. We are going to start one.

        Here is what I want to build, in my words:

        \(description)

        First, ask me what you actually need to know — never as an open question. Come
        with the answers already worked out: two to four concrete options, numbered,
        your recommendation first and marked as such, so I can answer with a single
        character. If none of them fit I will tell you.

        Ask about what is missing or ambiguous in what I just told you: who it is for,
        the features, the constraints, what is out of scope, and what has to happen
        before what. One question at a time, a handful of them rather than an
        interrogation, and write no files while we are talking.

        Then draft the plan, before writing any of it, so I know what I am getting and can
        change it while that is still cheap.

        It all goes into `\(folderName)/` in this folder — every file this produces goes in
        there and nowhere else. Do not create roadmap/, projects/, tasks/ or runs/ at the
        project root, and leave everything outside `\(folderName)/` untouched.

        Start with `\(folderName)/\(specFile)`, the format below, verbatim. Then write the
        draft as one file, `\(folderName)/blocks/plan.md`, with this frontmatter:

            ---
            id: plan
            kind: proposal
            title: "Plan for <what this project is>"
            status: open
            stage: ready
            session: \(sessionID.uuidString.lowercased())
            action: "Return to the setup session to change the plan."
            created: YYYY-MM-DD
            updated: YYYY-MM-DD
            ---

        Its body, in this order:

        - What I will have once every task has landed, in my words: what someone can do
          with it, not how it is built.
        - My goals as roadmap entries, and the projects that get us there, each with its
          outcome, `depends_on` where one blocks another, and `repos` naming the folders
          its work lands in.
        - Every task, grouped by project in build order: its id, one line on what it
          changes that I could see or check, its `depends_on`, and its Done when.
        - Which tasks can start together. Order matters more than volume — the
          dependencies are what I am going to read.
        - The calls you made where I left something vague, and what is left out.

        Each task goes to an agent of its own, which gets that task's file and the files of
        what it depends on, and nothing else. Cut the tasks so that is enough:

        - A task is the smallest change someone could see work or check on its own, with a
          `## Done when` checklist another agent can verify.
        - `depends_on` names only what a task cannot start without — something another
          task builds that this one uses — never just the order you would do them in. The
          task's Context says what it takes from each.
        - Tasks with no dependency between them never change the same screen, endpoint or
          module. Where two would, merge them or make one wait on the other.

        Then stop, tell me the draft is under Blocks, and wait. When I ask for changes,
        change that file and nothing else, and tell me what moved. Write no roadmap,
        project or task file until I approve the draft, with its `Create project` button
        or in my own words.

        Once I approve, write the files it describes, following the format's frontmatter
        exactly: the roadmap entries, the projects, each carrying its `roadmap:`,
        `depends_on` and `repos`, and the tasks, each carrying its `project:` and its own
        `depends_on`. Record every call you made as one memory entry in the project it
        affects, saying what you assumed and why. Leave `owner` and any unknown date empty
        rather than inventing one. Then set the draft's `status: done` with
        `resolution: "Wrote the notebook."`.

        Before your final reply, append one run record under `.notebook/runs/` for this
        setup session. Use the primary roadmap id as `subject`, summarize the result in
        the first body paragraph, and put corrections or unfinished work under
        `## Handoff`. Do not copy the transcript into it.

        When the files are written, stop and tell me in a few lines what you created, then
        wait for my corrections.

        Here is the format to write verbatim to `\(folderName)/\(specFile)`, and then follow:

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

    /// The reusable skill owns orchestration; the opening prompt only carries the batch.
    /// The session id goes in so a block this lead writes says who is waiting on it —
    /// with two leads running, the answer has to come back to the right one. An empty
    /// batch is a lead started with no work: it confirms the team and waits.
    package static func engineeringPrompt(tasks: [NotebookCard], sessionID: UUID, agent: AgentKind) -> String {
        let id = "Session id: \(sessionID.uuidString.lowercased())"
        let batch =
            tasks.isEmpty
            ? "\(id)\n(No tasks yet — stand by: confirm the team roster and wait for a batch.)"
            : "\(id)\n\(taskList(tasks))"
        return agent.skill("engineering-lead", arguments: batch)
    }

    /// A change request with no lead left to type it into: a fresh lead gets the task and
    /// the user's comments together, and the skill tells it to read the earlier records.
    package static func changeRequestPrompt(
        task: NotebookCard, message: String, sessionID: UUID,
        agent: AgentKind
    ) -> String {
        agent.skill(
            "engineering-lead",
            arguments: "Session id: \(sessionID.uuidString.lowercased())\n"
                + "\(taskList([task]))\n\n\(message)")
    }

    /// Reinvoke the same dispatcher for a later batch in the existing lead session.
    package static func additionalTasksPrompt(tasks: [NotebookCard], sessionID: UUID, agent: AgentKind) -> String {
        engineeringPrompt(tasks: tasks, sessionID: sessionID, agent: agent)
    }

    /// Product writes its session id into the Blocks notification, making that row a link
    /// back to the transcript where the proposal is discussed.
    package static func productPrompt(arguments: String, sessionID: UUID, agent: AgentKind) -> String {
        agent.skill(
            "product",
            arguments: arguments
                + "\nSession id: \(sessionID.uuidString.lowercased())")
    }

    /// Opens the session that walks the user through one block — a forward-deployed
    /// engineer, whose skill owns how to guide. The prompt only says which block, because
    /// the file already carries the rest: SRE's step-by-step procedure to deliver one step
    /// at a time, and the way back — setting `status: done` in it releases the session
    /// waiting behind it.
    /// The resumable prompt for a block. Live proposals route directly to their Product
    /// transcript; this is also the fallback when that Product session has exited.
    package static func unblockPrompt(block: UserBlock, agent: AgentKind) -> String {
        agent.skill(block.isProposal ? "product" : "fde-dev", arguments: relativePath(block.url))
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
