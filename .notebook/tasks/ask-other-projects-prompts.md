---
id: ask-other-projects-prompts
kind: task
title: "Tell agents to ask"
status: active
depends_on: []
designer: ""
project: cross-project-requests
owner: ""
created: 2026-10-01
updated: 2026-10-06
external: {}
---

Every agent handed another project's folder is told to ask that project for a change rather than
make it, and Product knows what to do when another project asks it.

## Done when

- [ ] `NotebookFormat.readingNote` still says change nothing there, and now says how to ask:
      write a message in this project's `.notebook/messages/`, in the memory's shape, and carry
      on with what does not need the answer. Product and assigned sessions both get it.
- [ ] One new function in `NotebookPrompts.swift`, taking plain strings — the sender's folder
      relative to the receiver, the sender's session id, the title and the body — returns the
      text the app types into the receiving session, including how to reply (`to` and
      `reply_to` filled in for it).
- [ ] `Skills/product/SKILL.md` Describing step 3: when the request needs a change in a tagged
      project, message it and fit this project's tasks around its answer, naming its tasks in
      their Context. A new mode, `asked`, for a message from another project: file the part
      straight onto this board as Describing does, put questions to the asking session as a
      message rather than to the user, and answer with what landed and what the asker can rely on.
- [ ] `docs/guide/product.md` says what happens when a request tags a project whose part changes.
- [ ] Prompt tests cover the reading note and the new function; `make check` passes.

## Context

The shape is in [[message-file-shape]]; the reasoning in [[other-project-files-its-own-part]]
and [[depends-on-stays-in-one-notebook]]. Area: `Sources/YongkangCore/Prompts/NotebookPrompts.swift`,
`Skills/product/SKILL.md`, `docs/guide/product.md`. What crosses into
[[deliver-project-messages]]: the new function's name and arguments, said in the report.

## Constraints

Skills are product source; the app bundle copies them on every build. Keep the skill's existing
modes working as they are.
