import Foundation

extension NotebookFormat {
    /// How every plan reaches the user's eyes — a new notebook, a described feature, a
    /// review's next move — so setup and Product draw the same map. A graph, not the draft's
    /// lists, because the dependencies are what the user reviews; Mermaid, because any agent
    /// writes it and it lays the arrows out itself.
    private static let planGraph = """
        Whenever a plan with projects and tasks is ready for me under Blocks, and each time it
        changes, show it to me as a graph: an artifact if you can publish one, otherwise one
        HTML file in the system temp directory that you open for me. Never ask me to open files.

        Draw it with Mermaid from cdn.jsdelivr.net/npm as a `flowchart LR`: a subgraph per
        roadmap entry holding its projects, a subgraph per project holding its tasks, each task
        a node with its id and a few words on what it changes, and an arrow from every
        `depends_on` to what waits on it, between projects as well as tasks. Style design tasks
        apart, outline the tasks that can start at once, fade what already exists that the plan
        only builds on, and add a one-line legend. It maps the plan, not the product: no
        mockups.
        """

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
            title: "Plan for <what this project is>"
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

        \(planGraph)

        Once I approve, with `Create project` or in my own words, write the roadmap, project
        and task files, and one memory entry per call you made in the project it affects.
        Set the draft's `status: done` with
        `resolution: "Wrote the notebook."`, append one run record for this session with the
        primary roadmap id as `subject`, and tell me in a few lines what you created.

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
        productSkill(arguments + "\nSession id: \(sessionID.uuidString.lowercased())", agent: agent)
    }

    /// Every way into Product — a review, a described feature, a proposal reopened from
    /// Blocks — shows its plan as the same graph setup does.
    private static func productSkill(_ arguments: String, agent: AgentKind) -> String {
        agent.skill("product", arguments: arguments) + "\n\n" + planGraph
    }

    /// Opens the session that walks the user through one block — a forward-deployed
    /// engineer, whose skill owns how to guide. The prompt only says which block, because
    /// the file already carries the rest: SRE's step-by-step procedure to deliver one step
    /// at a time, and the way back — setting `status: done` in it releases the session
    /// waiting behind it.
    /// The resumable prompt for a block. Live proposals route directly to their Product
    /// transcript; this is also the fallback when that Product session has exited.
    package static func unblockPrompt(block: UserBlock, agent: AgentKind) -> String {
        block.isProposal
            ? productSkill(relativePath(block.url), agent: agent)
            : agent.skill("fde-dev", arguments: relativePath(block.url))
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
