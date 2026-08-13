# Claude Code.app

macOS window that runs multiple `claude` or `codex` CLI sessions in real PTYs (SwiftTerm). Add, switch, and close sessions from the left sidebar. Nothing starts until you pick a folder — that keeps macOS from prompting for iCloud Drive / Music / Documents, which is what happened when it defaulted to `$HOME`.

```sh
./make-app.sh && open .build/ClaudeCode.app
```

Requires `claude` and/or `codex` on your PATH (they launch via `zsh -ilc`, so `.zshrc` applies).

## Projects

A project is a folder. The app opens on the all-projects screen; click a card to enter
one, `‹ All Projects` (⌘[) to leave. Agents keep running while you are away — terminals
are hidden, never torn down.

Open projects come back on the next launch. Only the folders are remembered, not the
sessions — those PTYs died with the app — and a folder that has since moved is dropped
from the list rather than shown broken.

Inside a project the sidebar is its notebook and its sessions. Both belong to the
project: sessions run in the project folder, the notebook is `.notebook/` inside it.

## Notebooks

Every project has a notebook. It stays empty until you add an entry — nothing is
written to the folder before that, so opening a project never touches your repo.

An empty project opens a compose box instead of a blank pane: describe what the
project is for and press Return. That text starts a Claude Code session carrying the
notebook format. It fills the gaps with a few multiple-choice questions — never open
ones — then writes `.notebook/` without showing you a plan first — reading a real notebook on the board beats approving an
imaginary one. Calls it had to make on your behalf land as memory entries, so they are
visible and correctable. The app writes nothing; the agent does. Entries look like:

```
<project>/.notebook/
  NOTEBOOK.md                 the format, written for whichever agent reads it first
  roadmap/<id>.md             goals and bets
  projects/<id>/project.md    one project
  projects/<id>/memory/*.md   that project's memory, one fact per file
  tasks/<id>.md               shippable work, linked to a project by frontmatter
```

Every entry is Markdown with YAML frontmatter (`id`, `kind`, `status`, `depends_on`,
`project`, `external`). Nothing else stores state, so the agents in the sidebar edit
the notebook by editing files — no bridge, no API. The sidebar re-reads the tree every
2s, so entries an agent writes show up on their own.

## Board

`Board` at the top of a project's notebook lays the three kinds out in columns, each
ordered so nothing appears before what it depends on — the tasks column reads as the
build order. Cards show status and what they wait on; an id nothing resolves to shows
in orange, which is how you catch a typo in `depends_on`. Click a card to dim
everything unrelated to it, and again to clear.

Frontmatter keys are Notion properties, folders are databases, and `external.notion`
holds the page id, so an exporter to Notion (or any third-party notebook) is a pure
function over these files. `NOTEBOOK.md` spells out the mapping and the rules that keep
it true.

```sh
swift run ClaudeCodeApp --selftest   # checks the on-disk format has not drifted
```
