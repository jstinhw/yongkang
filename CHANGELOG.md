# Changelog

What changed in each release, newest first. Pushing a `vX.Y.Z` tag releases the section headed
`## [X.Y.Z]`: its notes become the GitHub release's and the update window's, and the release
workflow stops if the section is missing. Write under Unreleased as you go; `docs/release.md`
has the rest.

## [Unreleased]

## [0.1.0] - 2026-10-11

The first public release. Yongkang runs a team of agent CLIs — `claude`, `codex`, `grok` and
`agy` — in real terminals against a project's `.notebook/` folder, and reviews the changes they
leave behind. It needs macOS 14 or later and at least one of those CLIs on your PATH.

### Added

- **One window for every project.** Each open folder is in the sidebar with its running sessions
  or active tasks under it, amber when something needs you and green when work waits for review.
- **The notebook.** A project's roadmap, milestones, tasks and memory are Markdown files in
  `.notebook/`, and they are the only state. Describe a new project and an agent drafts the plan
  for you to change before it writes any of it.
- **Board.** Each milestone's tasks in the order they wait on each other; a card with no line
  above it can start now.
- **Agents.** Assign a task, a milestone or a batch to Claude Code, Codex, Grok or Agy. Tasks
  that wait on nothing run side by side, one session each; a chain of dependent tasks shares
  one. **New Terminal** (⌘T) opens a plain shell in the project.
- **Requests.** **New Request…** (⌥⌘N) files what you ask for on the board, and asks any other
  project you tag for its part.
- **Design before code.** A task that changes something you can see is built first as a running
  demo, shown beside the screen it would replace, and waits for your approval.
- **Blocks.** What only you can do — an account, a secret, a command to run — waits as one short
  ask, and the agent that hit it takes you through it.
- **Review.** No agent commits. A finished task opens on what changed, how the agent checked it
  and how sure it is; the diff is a click away, and approving commits it.
- **The team.** Agents with skills of their own, one file each in `.notebook/team/`, added from a
  form, a git repo of skills, or a description.
- **Usage.** What every project's agents have spent, and how close each tool is to its plan's
  limits.
- **Updates in the background.** A new version downloads by itself: **Yongkang → Restart to
  Update** installs it, and quitting installs it anyway. **Check for Updates…** asks straight
  away.
