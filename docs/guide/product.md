# Product review

![A Product session's transcript](../images/session.png)

`New request` at the bottom of the board — or `Agent ▸ New Request…` (⌥⌘N) from any
screen — opens a box where the bar was. Say what you want in your own words and `@`-tag
what it is about: `@app/page.tsx` is a file in this project, `@/notebook-sync` another
project in the same sidebar group, and `@../personal/blog` one in another group (`@../name`
for a project in no group). A project's tag is a folder, so Tab walks into its files:
`@/notebook-sync/Sources/Sync.swift`. Product reads what you tagged, but files the work in
this project's notebook only.

When the request needs a change in a tagged project as well, Product does not make it there.
It writes that project a message, and a Product session opens under that project in the
sidebar — or the one already running there gets it — with the message typed into its
terminal. That Product files its part on its own board, marked `new` with its own `Approve
and commit`, and answers; the answer is typed into this Product's session, which fits this
project's tasks around it and names the other project's tasks in their Context. Approving
here approves the other board's part too, and any part it asked for in turn; each board
commits only its own files. A part whose Product is still working is left on its board, and
you are told. A session you hand other folders to read from `New Agent` asks
the same way.

Product files the request straight onto the board: tasks under an existing milestone when
the request serves it, otherwise a new milestone, with what waits on what decided for you.
There is no proposal to approve first; the board stays on screen, and what Product filed is
marked `new` under a line saying what landed. `Ask for changes` opens the box again and sends
what you type to the same Product session; `Open session` shows its transcript. Once Product
has stopped, the same line sits on top of its session too — its transcript and the plan on
the **Plan** row under it — so you can decide where you read it. `Approve and commit` commits the uncommitted
roadmap, milestone, task and memory files, and the session's own plan and the messages it
sent other projects — never the file of a task handed to an agent, which goes in with that
task's review — then closes the request and the Product session.
What is uncommitted is read from git, so a relaunch brings an unapproved request back, and so
does the end of any Product turn that leaves a plan uncommitted — one asked for in its
terminal, or after the line was dismissed. A plan you commit yourself instead closes the
Product session once its turn is over, the way approving it would have: what its request
filed is all committed, or, after a relaunch, its Page is — the app commits a Page only
with the approval that closes its session, so one in git went in with your commit.
Nothing is assigned or run until you pick it.

`Product review` at the bottom left of the board — or `Agent ▸ Product Review`, which works from any screen —
starts a session that reads the whole notebook — roadmap,
projects, tasks, memory, the last run records — inspects the product, researches relevant
current alternatives when useful, and works out what should come next. It presents at
most three ranked directions in the Product transcript and asks for feedback there. One
`.notebook/blocks/` notification links back to that same conversation; draft alternatives
do not become separate proposals and looking at the board does not move it.

Once the decisions are settled, Product replaces that notification with the complete
proposal: what you will have once every task lands, roadmap impact, project,
dependency-ordered tasks, agent resources and the rationale for each.

Either way, the tasks are cut to be handed out. Each is the smallest change that can be
checked on its own, depends only on what it actually uses from another task and says
what that is, and never touches what a task it doesn't depend on touches. The proposal
lists which tasks can start together: those can go to separate agents at once. `Request changes` returns to the Product transcript. `Create project`
is the explicit approval that writes the roadmap changes (when proposed), project and
tasks to the notebook. Nothing is assigned by that; picking stays yours — but the whole
project goes in one gesture when you want it to, `Pick all` on its page.
