# Shipping tasks

![A task's review, opened from its row under its session in Agents](../images/agents.png)

Every Assign button has an agent picker beside it — Claude Code, Codex, Grok or Agy —
starting on the toolbar's agent. Picking one there is for that assignment only; the
toolbar keeps its default.

What you assign is split into chains, and each chain gets a session of its own, named
after the coding agent running it — Claude Code, Claude Code 2 — with its tasks listed under
it in `Agents` by their own names:

- **A task:** `Assign` on its page starts one session on that task, together with any
  unfinished tasks it waits on — those cannot run beside it, so they share its session and
  go first.
- **A project:** `Pick all` on the project's page, or `Assign all tasks to` on its row in
  the list, takes every open task of its. Tasks that wait on nothing start side by side,
  one session each; a chain of dependent tasks is one session that works down it.
- **A batch:** tasks picked on the board are split the same way.

One session opens in the window. Several go to the project's Agents page, which shows each of
them, so they are all in sight even with the sidebar hidden. `New Agent` (⌘N) assigns one task
from any open project the same way, and can hand the session other folders to read — see
[Projects](projects.md#new-agent). A session
already running is never handed more, because its agent may not be the one you picked, and
a task a session already holds cannot be assigned again until that session exits.

There are no specialist roles. Each session reads its tasks, what they depend on and the
project's memory, and does the work; the prompt only carries what the app reads back:

- set a task `active` when it starts and `done` once every item of its `Done when` is
  checked;
- a task with `designer:` set goes through the `designer` skill, and nothing waiting on it
  starts until you approve the demo — see [Design before code](design-gate.md);
- anything only you can do becomes a block — see [Blocks](blocks.md);
- nobody commits, pushes, branches or opens a PR. A session holding tasks is refused
  those commands outright (`--disallowedTools` for Claude Code, `--deny` for Grok), and
  the work waits uncommitted for you in [Review](review.md).

```mermaid
flowchart TD
    A[Assign a task or a project, on the agent you pick] --> B{Split into chains}
    B -->|a task waiting on nothing| C[Its own session]
    B -->|a task and what it waits on| D[One session, in depends_on order]
    C --> E[Report per task: Result, Verification, paths]
    D --> E
    C -->|design task| F[designer skill, demo in Blocks]
    F -->|you approve| E
    C -->|only you can do it| G[Block]
    G -->|resolved| C
    E --> H[Review drawn from the report, work waits in Review]
```

For every task it writes `.notebook/runs/<session-id>-work-<work-id>.md` — the task id,
then `-2`, `-3` for a later attempt — with the files it changed in `paths`, a one-line
`report`, and `## Result`, `## Verification` and `## Review` in the body. That record is what
Review reads and what approving a task commits beside its code. `## Review` is JSON — a
one-sentence summary, a confidence, the checks it ran, the spots a person should read, its
questions and concerns — and the app draws the task's review from it, which also opens from
the **Page** row under the session in the sidebar. Nothing opens a browser. Setup and Product hand their plan over as
`.notebook/pages/<session-id>.json` instead, and the app draws it on the same tab: what you
get, what needs you, and the tasks as a graph you drag, zoom, and click to trace what a task
waits on and what waits on it.

The sidebar lists every running session under its project, by its own name, with what it is
doing and the task it is on, for every open project at once: needs you first, then ready for
review, then working. A session that has exited leaves the list; what it left waiting on you
still counts on its project, and waits on the board. The project's **Agents** page shows the
same sessions as cards in those three columns, with what each is asking, what it finished or what
its subagents are on, and the button that acts on it. Work is started from the board, or with
**New Agent**. A task's own page names who is on it under **Working
on it**: the session it was assigned to, and any subagent working it.

Clicking a session opens its live terminal, under what it is doing and the task it is on. Once a task is done and its files wait for your
approval, the session's row turns green — "ready for review" — and the task gets a row of its
own under the session in the sidebar, which opens the task and its review — see [Review](review.md). A session blocked on one
task while another waits for review gets a second, green row for the finished one, so the work
is never hidden behind the block. Approving from the review stays on the task. Work whose own
report argues against approving it — a check that failed, a concern it says blocks, a low
confidence — is not ready for review: its row is amber and says why, and its board card reads
**caution**, until you send it back or approve over it.

A subagent is linked to its task by its own name, which the prompt asks to be the task id;
Claude keeps that as the subagent's description and Codex slugs it into the spawned thread's
name, and the app matches it back either way. Clicking a subagent, on its session's page or
under **Working on it** on a task's page, opens the CLI's live child view: the app opens
`/tasks` in Claude Code or `/subagents` in Codex and selects the matching row. **Parent
session** returns to the session.

Claude subagents are read from
`~/.claude/projects/<slug>/<session-id>/subagents/`; Codex, which picks its own thread id
rather than taking one, is found by the session id the app's opening prompt quotes and
then by the rollouts in `~/.codex/sessions/` pointing back at that thread.
Grok transcripts and usage are read from its UUID-addressed session under
`~/.grok/sessions/<encoded-project>/`; Agy currently runs in its live terminal only.
