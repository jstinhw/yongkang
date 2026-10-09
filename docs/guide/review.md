# Review

No agent commits. A task the agent marked done waits with its work uncommitted, and you
decide: approve it, which commits it, or send it back with what to change. A review opens
from the agent's row in the sidebar, green while its work waits, or from the **Review** button on
its card under the project's Agents page; the project's row counts what is waiting in green, and
the rail's Agents icon lights green while anything in any project is.

A project with a notebook that is not a repository is made one (`git init`) the first time
the app reads git in it — which is on any screen, not only a review, because that light has
to come on while you are looking at another project. There is no diff and nowhere to commit
without a repository. Nothing is staged or committed by that.

The whole working tree, including edits no task claims, is one page of its own, reached
from **All changes** on a task's review.

A task opens on what most reviews need, not on code, and is meant to be understood in ten
seconds. Under the title, one sentence of what changed, then four tiles:

- **Agent's confidence** — high, medium or low, and why, in the agent's words.
- **Checks it ran** — how many passed, one dot per check, and how many failed or could not
  run here.
- **What it touches** — the agent's few words for it, over git's count of files and lines and
  their areas, so the one tile it could get wrong has the numbers beside it.
- **Needs you** — open blocks, unanswered questions and the spots it wants read.

Then the cards, most urgent first:

- **Needs you** — a block or demo holding the task: its title, what is needed and the steps,
  with **Walk me through it** (or **Open the demo**) and **Open the block**. Under it, the
  agent's questions, each answered with one click on an option (the one it would pick is
  filled) or in your own words; the answer is typed into the session holding the task, with
  none running a new one starts with it, and the card says **Sent**. Then the spots: the few
  places the agent says a person should read because no check covers them, each with why,
  unfolding its own lines of the diff, where a line can be commented on.
- **What changed** — outcomes you can see or check, with the agent's full report
  (`## Result`) one click below.
- **Why it's safe** — every check it ran, what it proved and, one click away, the command and
  what it printed; one it could not run is listed in amber rather than left out. Then what
  keeps the work safe whatever the code does.
- **Concerns it raised** — each saying whether it should be settled before approving.
- **Code changes** — the task's files grouped as Database, API & services, Frontend,
  Tests, Config, Docs & other, and Notebook records, each with the lines it added and removed.
  The area is worked out by the app from the path, SQL in the diff, and the owning agent's
  skill, so a data layer that writes SQL is flagged as Database even with no migration
  folder. Every file starts folded; clicking one unfolds its diff in place.
- **Feedback** — each earlier round, what you asked and what the agent said it did about
  it, then what goes in the next one.

Click any line of an unfolded diff to leave a comment on it; comments and a note for
anything that is not about one line collect under **Feedback** until you send them. The same
page opens from the agent's row in the sidebar and from its page's **Waiting for your review** — see
[Shipping tasks](engineering-lead.md), and from the session's **Page** row. The inspector carries the task's brief and
`Done when`, what the agent did outside the repo (network reads, downloads, writes — or
nothing), what landing it unblocks, the areas, what the commit will hold, and a warning when a
file is also changed by another task still waiting.

All of this is drawn from the `## Review` the agent writes into its run record, as JSON, so
every review reads the same whichever agent wrote it. A record without one — from a session
started before reviews — opens on **The task**, **What changed** in the agent's words and
**Self-review**, its `## Verification`; one the app cannot read says which field was wrong. A
failed check, a low confidence or a concern that blocks makes the button **Approve anyway**,
and no longer the primary.

The bar at the bottom is the decision, on the task page and on its diffs alike:

- **Approve and commit** stages and commits only this task's files and its run records —
  whatever else is in the tree or the index is left as it was. Nothing is pushed.
- **Request changes** types `Changes requested on <task-id> — "<task title>".`, your note
  and every line comment (`path:line`, with the code it is about) into the session holding
  the task. With none running, a new one starts on the toolbar's agent with the task and the
  comments. It answers them as a new attempt, checks the `Done when` again, and the task
  comes back to **Waiting for you**.
- **Discard and rerun** asks first, then throws the attempt away: the task's files go back
  to the last commit, the new ones and its run records are deleted, and nothing else in the
  tree is touched. The task's `status` goes back to `todo` and the rest of its file stays as
  it is. Then the task goes to an agent the way **Request changes** does, to be done again
  from the start.
- **Discard** on the board's task page does the same without starting an agent, for a task
  that is ready for review, demo ready or blocked. Its open demo or block is closed too, and
  the task waits on the board as `todo`, for you to assign it again when you choose.

None of it is written for this screen; it is the run records in `.notebook/runs/`, where
`paths` on each work record is what attributes a file to a task. They are read from disk,
not from the sessions open now, so work stays waiting for review after a relaunch or after
its session is closed. A task turning `done`
opens its review by itself, unless a terminal is up — that pane has the keyboard.
