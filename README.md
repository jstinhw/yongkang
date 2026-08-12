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

Inside a project the sidebar is its notebook and its sessions. Both belong to the
project: sessions run in the project folder, the notebook is `.notebook/` inside it.

## Notebooks

Every project has a notebook. It stays empty until you add an entry — nothing is
written to the folder before that, so opening a project never touches your repo.

An empty project opens a compose box instead of a blank pane: describe what the
project is for and press Return. That text starts a Claude Code session carrying the
notebook format, primed to question you about the rest, show you a plan, and only
then write `.notebook/`. The app writes nothing — the agent does, from what you told
it. Entries look like:

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

Frontmatter keys are Notion properties, folders are databases, and `external.notion`
holds the page id, so an exporter to Notion (or any third-party notebook) is a pure
function over these files. `NOTEBOOK.md` spells out the mapping and the rules that keep
it true.

```sh
swift run ClaudeCodeApp --selftest   # checks the on-disk format has not drifted
```
