---
id: who-asked-and-who-waits
kind: memory
title: "Who asked and who waits"
project: cross-project-requests
subject: cross-project-request-ui
memory_type: decision
source: agent
supersedes: []
created: 2026-10-06
updated: 2026-10-06
external: {}
---

What the model exposes for the UI:

- **Who asked a request:** `ProjectModel.request?.from`, the asking project's folder (a `URL`),
  set when another project's message started the request. Nil for a request typed on this board.
- **Who is waiting:** `ProjectModel.waitingOn[session.id]`, the folder of the project that
  session wrote to and has had no answer from since. It is cleared when an answer is typed in,
  and set again when the session writes another message. Whoever spoke last decides.

Map a folder to its name by finding the open `ProjectModel` at that `directory`, or use
`lastPathComponent`.

## Why

Both are in memory only, set as `AppModel.deliverMessages` types each message in. After a
relaunch they are empty until the next message either way: `resumeRequest` rebuilds a request
without `from`. Persist them next to `AppModel.deliveredMessages` if the banner or sidebar must
say who is talking straight after a relaunch.
