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

Nothing starts until you press `Do it now`. Then the app hands the gate back to the agent that
wrote it — the same session, still on the same task, so there is one thread and one row rather
than two agents with the same name. It does every step that does not need you first, and a
good many gates turn out not to need you at all: a CLI already logged in, a repo that already
exists. Those clear themselves without asking you anything. If that agent has since gone, a
session is opened for the gate alone, named after the gate. Once it clears, the task starts again
with an agent of its own, and the gate's session closes when it has finished and you have moved
on.

When one genuinely needs you, that session finishes its turn and says so the way any agent
does, with a banner and an amber row. It explains in two or three lines what is being set up,
then takes it one step at a time — one instruction, verified before the next, and never a
secret echoed back or written down. The page each step needs is beside the session, inside the
window: the agent keeps the block's `url:` pointed at it rather than opening a browser behind
the app. Pressing `Do it now` again goes to that session; it does not start a second one.

Sometimes the step is a command only you can run — one the agent's sandbox refused, like moving
your branches onto rewritten history. The agent never asks for it in its reply alone. It puts
the exact command in the block's `run:`, and the pane beside the session switches from the page
to the command, with an **Approve and run** button and every file it runs drawn in full, read
from disk rather than described by the agent: the script it names, a second script that one
calls, a program a script puts on `PATH`. Lines that talk to a server, delete files, rewrite history, change a
remote or run as administrator are marked, and listed at the top under **What it touches**.
That list is a pattern match, not a review, and the pane says Yongkang has not checked that the
command is safe; the agent's reply says in plain words what it changes and what cannot be
undone, so you can hold one against the other. Characters that show differently than they run
— a bidi override, a zero-width space — are written out as `⟨U+202E⟩` and flagged. The files are
read again every two seconds, whatever their dates say, and one rewritten while it is on screen
says so. The command is split the way the shell splits it, quotes and all. Each program it runs
by bare name is listed under **Programs it runs** with where it is found — on your shell's `PATH`
first, then the app's — and every match, when there is more than one, since a script early on the
`PATH` runs in place of the `git` you meant; any script among them is drawn. A path the shell only fills in
when it runs — `$S/finish.sh`, `*.sh` — is listed as one Yongkang can't tell you about, with a
note to have the agent write it out. Only scripts are drawn unasked: a file the command reads,
or one named like a key, waits behind **Show**, since a token can sit in any of them. A program
that is not text is named with its size and a note to ask what it is, and a command that runs
more files than the pane shows says that too. The caption names the folder the session runs in,
since a relative path means another file anywhere else. The button waits until every file is on
screen, and approving types the command after `!` in the session beside the pane, once: its
output lands there, for you and the agent both. The page is one click away under **Page**; once
the command has run, the agent clears `run:`.

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
