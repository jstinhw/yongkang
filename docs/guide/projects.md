# Projects

![The all-projects screen](../images/fleet.png)

Nothing starts until you pick a folder — that keeps macOS from prompting for iCloud
Drive / Music / Documents, which is what happened when it defaulted to `$HOME`.

A project is a folder. The app opens on the all-projects screen; click a card to enter one.
Inside a project, its name at the top of the list is a menu: pick another open project to
switch to it, or `All Projects` to leave. While the list is hidden (`⌘\`) the same menu sits
in the toolbar beside the list button, and `Go ▸ All Projects` (⌘[) works from anywhere. A project with something waiting on you says so in that menu. Right-click a card to reveal its folder or remove it
from the screen; the folder stays on disk. Agents keep
running while you are away: terminals are hidden, never torn down.

Two tiles sit at the end of the grid, one per door, and the `File` menu opens either from
anywhere, including from inside another project. `Describe a new project…` (`File ▸ New
Project…`, ⌘N) opens a prompt: say what to build and tag anything it should read with `@`. Where the folder
goes is worked out from the prompt — `~/code/todo` in it is enough. Otherwise it lands beside
the projects you already have (`~/Projects` on a first run), and when you press Return the
agent selected in the toolbar reads the description and names it: a few seconds for Claude
Code, longer for some CLIs. No path is shown before you press Return. If the
agent cannot answer — not signed in, no network — the box says why and nothing is created;
naming a path in the prompt skips the question. The folder is
created and the prompt goes straight to the session that writes its notebook.
`Open a folder you have` (`File ▸ Open Folder…`, ⌘O) is the other door, for a folder that
already exists; an empty one asks what it is for on the way in.

Open projects come back on the next launch. Only the folders are remembered, not the
sessions — those PTYs died with the app — and a folder that has since moved is dropped
from the list rather than shown broken.

Inside a project, `Overview` is what it is doing right now: the agents running, what is
waiting on you, what changed on disk, and what the agents last wrote to the notebook.
Everything on it is read from the notebook, the transcripts and git — the app keeps no
state of its own to drift.

Inside a project, use the Agent switch in the window's toolbar to choose Claude Code, Codex,
Grok, or Agy. The choice is remembered and applies to new notebook setup, Product, Engineering
Lead, unblock, and plain sessions; sessions already running keep their original agent.
