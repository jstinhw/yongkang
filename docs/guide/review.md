# Review

No agent commits. A task QA passed waits in `Review` with its work uncommitted, and you
decide: approve it, which commits it, or send it back with what to change. The rail's
Review icon lights green while anything is waiting, and so does each waiting task's row.

A project with a notebook that is not a git repository is made one (`git init`) the first
time Review looks at it — there is no diff and nowhere to commit without one. Nothing is
staged or committed by that.

The list column is tasks, not files: **Waiting for you** (done, work still uncommitted),
**With the agents** (still being built or checked), and **All changes** for the whole
working tree, including edits no task claims.

A task opens on what most reviews need, not on code:

- **The task** — its brief and `Done when`, read from the task file.
- **Reviewer** — QA's verdict, as pass or fail, with the `## Result` it wrote: the
  commands it ran, what they said, and what it could not exercise.
- **What the agents did** — each specialist in its own words (`## Result`, or its report),
  with model, time and the files it owned. A later attempt shows the comments it was
  answering under **You asked**.
- **Changes by area** — the task's files grouped as Database, API & services, Frontend,
  Tests, Config, each with the lines it added and removed. The area is worked out by the
  app from the path, SQL in the diff, and the owning worker's skill, so a data layer that
  writes SQL is flagged as Database even with no migration folder.

A file opens its diff on its own page. Click any line to leave a comment on it; comments and a note for
anything that is not about one line collect under **Feedback for the agents** until you
send them. The inspector carries the verdict, the areas, what the commit will hold, and a
warning when a file is also changed by another task still waiting.

The bar at the bottom is the decision, on the task page and on its diffs alike:

- **Approve and commit** stages and commits only this task's files and its run records —
  whatever else is in the tree or the index is left as it was. Nothing is pushed.
- **Request changes** types `Changes requested on <task-id>`, your note and every line
  comment (`path:line`, with the code it is about) into the lead holding the task. With no
  lead running, a new one starts with the task and the comments. The lead sends each
  comment to the owner of that file as a new attempt, reruns QA, and the task comes back
  to **Waiting for you**.

None of it is written for this screen; it is the run records in `.notebook/runs/`, where
`paths` on each work record is what attributes a file to a task. They are read from disk,
not from the sessions open now, so work stays waiting for review after a relaunch or after
its lead is closed. A task turning `done`
opens its review by itself, unless a terminal is up — that pane has the keyboard.
