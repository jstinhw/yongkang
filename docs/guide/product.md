# Product review

![A Product session's transcript](../images/session.png)

`New request` at the bottom of the board — or `Agent ▸ New Request…` (⌥⌘N) from any
screen — opens a box where the bar was. Say what you want in your own words and `@`-tag
what it is about: `@app/page.tsx` is a file in this project, `@/notebook-sync` another
project in the same sidebar group, and `@../personal/blog` one in another group (`@../name`
for a project in no group). A project's tag is a folder, so Tab walks into its files:
`@/notebook-sync/Sources/Sync.swift`. Product reads what you tagged, but files the work in
this project's notebook only.

Product files the request straight onto the board: tasks under an existing milestone when
the request serves it, otherwise a new milestone, with what waits on what decided for you.
There is no proposal to approve; the board stays on screen, and what Product filed is marked
`new` under a line saying what landed. `Ask for changes` opens the box again and sends what
you type to the same Product session; `Open session` shows its transcript. Nothing is
assigned or run until you pick it.

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
