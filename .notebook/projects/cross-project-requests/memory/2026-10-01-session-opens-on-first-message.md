---
id: session-opens-on-first-message
kind: memory
title: "Session opens on first message"
project: cross-project-requests
subject: cross-project-requests
memory_type: assumption
source: agent
supersedes: []
created: 2026-10-01
updated: 2026-10-01
external: {}
---

The session in the other project opens when this project's agent first writes to it, not as
soon as a request tags that project. A tag is often for reading only — "do it the way
`@/site/` does" — and a session per tag would open Product sessions nobody needed. For a
request whose change spans both, the first message comes within the request's first turn, so
both sessions are open almost at once.
