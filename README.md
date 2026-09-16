# Yongkang

A dark console for running an agent team: multiple `claude`, `codex`, `grok`, or `agy`
CLI sessions, the notebook they work from, and the changes they produce.

![Yongkang](docs/images/overview.png)

Every screen has the same columns: a **rail** picking the section, a **list** of that section's
objects, the **work area** holding whichever one is selected, and on most screens an
**inspector** carrying what you would otherwise have to go and find. The rail's sections are
Overview, Board, Agents, Review and Blocks. The list is the window's sidebar, so you can drag it
wider or collapse it; the screen's name and the project are the window's own title and subtitle.

Every action is also a menu item, because a shortcut hung on a button only answers while that
button is drawn. File, View, Go and Agent hold `⌘N`, `⌘O`, `⌘1`–`⌘5`, `⌘\` and `⌘[`.

## Requirements

- macOS 14+
- Xcode 16 or later to build the app. On Xcode 26, also run
  `xcodebuild -downloadComponent MetalToolchain` once: Xcode compiles SwiftTerm's shaders.
- At least one of `claude`, `codex`, `grok` or `agy` on PATH (they launch via `zsh -ilc`, so `.zshrc` applies)

## Build, run, test

```sh
make run                             # builds the app with Xcode and opens it
make check                           # format lint, build, and the tests
make shots DIR=/tmp/ui               # renders every screen to PNG, offscreen
make help                            # every target
```

The shots come from a fixed sample notebook, so two runs are comparable — except `review.png`,
`handover.png` and `usage.png`, which are drawn from whatever repository the command is run in
and from this machine's own agent transcripts.

## How it works

The `.notebook/` folder is the only state — the app keeps none of its own. It never
writes what the agents write, and no agent commits without your approval in Review.

```mermaid
flowchart TD
    A[Assigned task contracts] --> B[Lead: split scope and map dependencies]
    B --> C[Choose skills, models, estimates and parallel capacity]
    C --> D[Dispatch independent ready work]
    D --> E[Specialist A]
    D --> F[Specialist B]
    E --> G[Report to lead: changes, evidence, usage, remaining work]
    F --> G
    G --> H[Independent QA]
    H -->|Pass| I[Accept subtask and unlock dependents]
    H -->|Fail| J[Return reproductions to owner]
    J --> D
    I -->|More work| D
    I -->|All parent criteria met| K[Task done, waits uncommitted for your review]
    E -->|User gate| L[SRE block, FDE assistance]
    L -->|Resolved| D
    G --> M[Check estimates, live status and context]
    M -->|Context threshold| N[Save checkpoint and durable memory]
    N --> O[Native compaction or fresh worker handoff]
    O --> D
```

## Docs

- [Projects](docs/guide/projects.md) — folders, the all-projects screen, the Agent switch
- [Notebooks](docs/guide/notebook.md) — the `.notebook/` entries and how they're edited
- [Board](docs/guide/board.md) — the dependency-ordered task board
- [Design before code](docs/guide/design-gate.md) — the designer gate before engineering
- [Product review](docs/guide/product.md) — describing features and reviewing the product
- [Shipping tasks](docs/guide/engineering-lead.md) — the Engineering Lead and its subagents
- [The team](docs/guide/team.md) — the roster in `.notebook/team/`
- [Review](docs/guide/review.md) — approving and committing agent work
- [Blocks](docs/guide/blocks.md) — gates only you can clear
- [Notebook format](docs/notebook-format.md) — the spec written to `.notebook/NOTEBOOK.md`
- [Development](docs/development.md) — contributing to the app itself
- [AGENTS.md](AGENTS.md) — instructions for agents working in this repo
- [Refactor plan](docs/refactor-plan.md) — the decisions behind this repo's shape
