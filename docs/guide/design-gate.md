# Design before code

![A demo waiting for approval, beside the screen it would replace](../images/demo.png)

A task that changes something you can look at is designed, and approved by you, before
anyone builds it. Nothing is inferred: Product decides, and writes `designer: <name>`
into the task's frontmatter. Empty means ordinary work that goes straight to the agent.

When a session picks up such a task it sets `status: designing` and runs the `designer`
skill on it first. The designer settles the layout in Claude Code's `/design` canvas,
builds it as a running demo on a throwaway `demo/<task-id>` branch, and writes one
`kind: demo` file to `.notebook/blocks/`. The rest of the session's tasks carry on
meanwhile — one demo does not idle the others.

The board shows that task as `demo ready` with `See demo`, which opens the two pages side
by side: the screen as it stands, and the screen this task would give you. `Before` is
empty and says so when the task adds a surface that does not exist yet. Every pass the
designer made is a chip on the `Revisions` strip, so you can follow how the change got
there rather than being handed one finished thing; a pass they kept serving opens again.

`Build it` clears the demo and tells the waiting session which revision won — only then
does the work on that screen start. `Request changes` opens the transcript of whoever
built it, because the point is that you say what is wrong in your own words. Saying no
throws the branch away; nothing was merged and no task status moved.
