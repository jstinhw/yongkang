---
id: read-project-messages
kind: task
title: "Read project messages"
status: done
depends_on: []
designer: ""
project: cross-project-requests
owner: ""
created: 2026-10-01
updated: 2026-10-06
external: {}
---

Core reads the messages an agent writes to another project, so the app can deliver them.

## Done when

- [x] A `ProjectMessage` type and `Messages.load(root:)` in `Sources/YongkangCore/Notebook/Messages.swift`
      read every `.notebook/messages/*.md` in the shape the project's memory fixes.
- [x] `NotebookSnapshot` carries them as `messages`, read on the same pass as `blocks`, and a
      write to `messages/` reaches the snapshot like a write to `blocks/` does.
- [x] A message missing `to` or `session`, or with a `session`/`reply_to` that is not a UUID, is
      skipped, not a crash; a quoted title with a colon reads whole.
- [x] Tests in `Tests/YongkangCoreTests/MessagesTests.swift` cover a first message, a reply and
      each malformed case; `make check` passes.

## Context

The shape is in [[message-file-shape]]. Read it the way `Blocks.load` reads `blocks/`, not
through `NotebookIndex`, whose line-by-line frontmatter parsing is the recorded known issue.
Area: `Sources/YongkangCore/Notebook/` and `Watching/ProjectReader.swift`. What crosses into
[[deliver-project-messages]]: `ProjectMessage` (its `to`, `session`, `replyTo`, `title`, `body`,
file URL) and `NotebookSnapshot.messages`.

## Constraints

Foundation only. `package`, not `public`, with an explicit `package init`.
