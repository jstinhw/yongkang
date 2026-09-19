# Review

No agent commits. A task the agent marked done waits in `Review` with its work uncommitted, and you
decide: approve it, which commits it, or send it back with what to change. The rail's
Review icon lights green while anything is waiting, and so does each waiting task's row.

A project with a notebook that is not a repository is made one (`git init`) the first time
the app reads git in it — which is on any screen, not only Review, because the rail's Review
light has to come on while you are looking at the board. There is no diff and nowhere to commit
without a repository. Nothing is staged or committed by that.

The list column is tasks, not files: **Waiting for you** (done, work still uncommitted),
**With the agents** (still being built or checked), and **All changes** for the whole
working tree, including edits no task claims.

A task opens on what most reviews need, not on code:

- **Needs you** — only while a block or demo holds the task: its title, what is needed and
  the steps, with **Walk me through it** (or **Open the demo**) and **Open the block**.
- **The task** — its brief and `Done when`, read from the task file.
- **What changed** — each attempt in the agent's own words (`## Result`, or its report),
  with time and the files it changed.
- **Self-review** — the `## Verification` the agent wrote on its latest attempt: the
  commands it ran and what they printed. A done task with none says nobody but you has
  checked it.
- **Code changes** — the task's files grouped as Database, API & services, Frontend,
  Tests, Config, Docs & other, and Notebook records, each with the lines it added and removed.
  The area is worked out by the app from the path, SQL in the diff, and the owning agent's
  skill, so a data layer that writes SQL is flagged as Database even with no migration
  folder. Every file starts folded; clicking one unfolds its diff in place.
- **Feedback** — each earlier round, what you asked and what the agent said it did about
  it, then what goes in the next one.

Click any line of an unfolded diff to leave a comment on it; comments and a note for
anything that is not about one line collect under **Feedback** until you send them. The same
page opens from the task's row under its session in `Agents` — see
[Shipping tasks](engineering-lead.md). The inspector carries the verdict, the areas, what the commit will hold, and a
warning when a file is also changed by another task still waiting.

The bar at the bottom is the decision, on the task page and on its diffs alike:

- **Approve and commit** stages and commits only this task's files and its run records —
  whatever else is in the tree or the index is left as it was. Nothing is pushed.
- **Request changes** types `Changes requested on <task-id> — "<task title>".`, your note
  and every line comment (`path:line`, with the code it is about) into the session holding
  the task. With none running, a new one starts on the toolbar's agent with the task and the
  comments. It answers them as a new attempt, checks the `Done when` again, and the task
  comes back to **Waiting for you**.

None of it is written for this screen; it is the run records in `.notebook/runs/`, where
`paths` on each work record is what attributes a file to a task. They are read from disk,
not from the sessions open now, so work stays waiting for review after a relaunch or after
its session is closed. A task turning `done`
opens its review by itself, unless a terminal is up — that pane has the keyboard.
