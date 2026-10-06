---
kind: run
session: a01a2f61-34c4-4c7c-995a-e4ae2368a4d1
task: read-project-messages
work_id: read-project-messages
title: "Core reads project messages"
status: done
paths: [Sources/YongkangCore/Notebook/Messages.swift, Sources/YongkangCore/Notebook/NotebookSnapshot.swift, Tests/YongkangCoreTests/MessagesTests.swift, .notebook/tasks/read-project-messages.md]
report: "ProjectMessage + Messages.load read .notebook/messages/, NotebookSnapshot.messages carries them; 8 tests, make check passed"
started_at: 2026-10-06T11:12:25Z
finished_at: 2026-10-06T11:15:18Z
---

## Result

- `Sources/YongkangCore/Notebook/Messages.swift` (new): `ProjectMessage` (`id`, `url`, `to`,
  `session`, `replyTo`, `title`, `body`, explicit `package init`) and `Messages.load(root:)`,
  which reads every `.notebook/messages/*.md` sorted by file name, the way `Blocks.load` reads
  `blocks/`. It uses the same `NotebookIndex.frontmatter`/`body` helpers as blocks, not
  `NotebookIndex.load`.
- A file is skipped, not a crash, when it has no `to` (or an empty one), no `session`, a
  `session` that is not a UUID, or a non-empty `reply_to` that is not a UUID. An empty
  `reply_to` (bare or `""`) is a first message, `replyTo == nil`. An empty title falls back to
  the slug. A quoted title with a colon reads whole.
- `NotebookSnapshot.messages` is read in `reread(frontmatter: true)` next to `blocks`, and a
  cheap read carries it over. The watcher already watches the whole project tree and every tick
  rereads frontmatter, so a write to `messages/` reaches the snapshot the same way a write to
  `blocks/` does. Nothing in UI changed.
- `messages/` is not in `NotebookFormat.folders`, so the notebook sidebar does not list it and
  the format contract is unchanged.

For [[deliver-project-messages]]: `ProjectMessage.to` is the raw string as written (for
example `../site`). Resolving it against the sender's folder and matching it to an open project
is left to delivery. `id` is the resolved file path, which is what to remember as delivered,
the way `deliveredBlocks` does.

## Verification

- `swift test --filter MessagesTests`: 8 tests, 12 cases, all passed. They cover no folder, a
  first message (with `reply_to: ""` as the parallel prompt task writes it), a reply, a quoted
  title with a colon, the slug fallback, five malformed cases (no `to`, empty `to`, no
  `session`, non-UUID `session`, non-UUID `reply_to`), a file with no frontmatter or not `.md`,
  and a written message reaching `ProjectReader.notebook(after:)` and surviving a cheap read.
- `make check`: exit 0 twice (11:13Z and 11:14Z): lint clean, build ok, "403 tests in 60 suites
  passed … with 12 known issues" (I added no known issues).
- A third `make check` at 11:15Z failed lint on
  `Sources/YongkangUI/Model/ProjectModel+Product.swift:29` (line too long). That file is being
  edited by another session (the prompts task) and I never touched it. At that point, on the
  same tree, `swift format lint --strict` on my three files was clean, `swift build` completed
  and `swift test` exited 0 with 403 tests passed.
- Shots: not rendered. Nothing a view draws changed. The snapshot gained a field that no screen
  reads yet.
