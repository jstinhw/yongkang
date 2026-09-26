# Blocks

![A block waiting on the user](../images/block.png)

Anything only you can settle lives in `.notebook/blocks/` and lights its project amber in the
sidebar, whichever project you are looking at — a product proposal waiting for your opinion, a
design waiting for your approval, or an agent that needs a token, a consent screen, an approval
and is sitting there until it has one. The agent holding it says so on its own row, and the
project's Agents page puts it first, under **Needs you**. The row says what is being asked and
what it holds up; the button sends it to whoever can act
on it, which for a proposal is product and for a gate is a session of its own.

A gate is written by the agent that hit it, and it keeps waiting. It writes the procedure
into the block under `## Steps` and carries on with whatever does not need it. That procedure
is addressed to the engineer who will work through it, not to you, so you are never shown it:
the block screen has the brief and `## Needed from you`, and nothing else.

You do not press anything to start. As soon as the file lands the app hands it straight back to
the agent that wrote it — the same session, still on the same task, so there is one thread and
one row rather than two agents with the same name. One gate at a time. It does every step that
does not need you first, and a good many gates turn out not to need you at all: a CLI already
logged in, a repo that already exists. Those clear themselves and you never hear about them. If
that agent has since gone, a session is opened for the gate alone, named after the gate.

When one genuinely needs you, that session finishes its turn and says so the way any agent
does, with a banner and an amber row. It explains in two or three lines what is being set up,
then takes it one step at a time — one instruction, verified before the next, and never a
secret echoed back or written down. The page each step needs is beside the session, inside the
window: the agent keeps the block's `url:` pointed at it rather than opening a browser behind
the app. `Do it now` on the block screen goes to that session; it does not start a second one.

Clearing it is one edit to the block file — `status: done` and a `resolution:` line —
made by that session, or by `Mark resolved` if you did it yourself. The app sees it on the
next read and tells the waiting agent to carry on. The file is the whole channel;
there is nothing else to keep in sync, and a block survives a restart.

Frontmatter keys are Notion properties, folders are databases, and `external.notion`
holds the page id, so an exporter to Notion (or any third-party notebook) is a pure
function over these files. `NOTEBOOK.md` spells out the mapping and the rules that keep
it true.

```sh
swift test                           # checks the on-disk format has not drifted
swift run shots /tmp/ui              # renders every screen to PNG from a fixed sample
```

`shots` draws each screen through an offscreen window, 1440×900 unless the screen is one of
the narrow variants that check the window's own minimum. A layout that clips or collapses is
invisible in a compiler pass and obvious in a picture, and the screens are too wide to check by
launching the app on every change. The one thing it cannot draw is the window's title bar, so
the toolbar and the menus are only ever checked in a running app.
