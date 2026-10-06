---
id: deliver-project-messages
kind: task
title: "Deliver project messages"
status: todo
depends_on: [read-project-messages, ask-other-projects-prompts]
designer: ""
project: cross-project-requests
owner: ""
created: 2026-10-01
updated: 2026-10-01
external: {}
---

The app types each message an agent writes into the right session in the other project, opening
one there when needed, so two projects' sessions can talk.

## Done when

- [ ] A message in project A to open project B with no `reply_to` opens a Product session under
      B in the sidebar — or is typed into B's running Product — and B's board treats it as a
      request: what Product files is marked new, and Approve and commit commits B's files only.
- [ ] A message whose `reply_to` names a running session in its project is typed into that
      session.
- [ ] A message whose `to` names no open project is answered in the sender's session in one line
      saying so.
- [ ] Each message is typed in once: not again on the next read, nor after a relaunch.
- [ ] Delivering never moves the window, in whichever project it lands.
- [ ] Approving A's request still commits A's files only.
- [ ] For [[cross-project-request-ui]], the model says who asked a request and which sessions
      are waiting on another project's answer.
- [ ] Tests in a new file under `Tests/YongkangUITests/` (`WorkflowTests.swift` is already over
      800 lines); `docs/architecture.md` says how a message travels; `make check` passes.

## Context

Takes from [[read-project-messages]] `ProjectMessage` and `NotebookSnapshot.messages`, and from
[[ask-other-projects-prompts]] the function that builds the text to type (named in its report).
Follow how `deliverUnblocks` types a cleared block into the waiting session, and
`ProjectModel.startProduct`/`sendRequest` for one Product per project and the `BoardRequest`
that drives the banner. Area: `Sources/YongkangUI/Model/` — a new `ProjectModel+Messages.swift`
and the per-project tick in `AppModel` (an extension file of its own if it grows).

## Constraints

The app never writes the message files: what it has delivered it remembers itself. Never log a
message's title or body.
