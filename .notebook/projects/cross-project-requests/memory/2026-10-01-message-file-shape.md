---
id: message-file-shape
kind: memory
title: "Message file shape"
project: cross-project-requests
subject: cross-project-requests
memory_type: decision
source: agent
supersedes: []
created: 2026-10-01
updated: 2026-10-01
external: {}
---

A message to another project is `.notebook/messages/<slug>.md`, written by the sending agent in
its own project's notebook, never the receiver's:

    ---
    kind: message
    to: "../other-project"   the receiving project's folder, relative to the sender's,
                             as the tag reached the agent
    session: <uuid>          the sending session's id
    reply_to: <uuid>         the receiving session this answers; empty for a first message
    title: "<a few words>"
    created: <RFC-3339>
    ---

    The message, in plain words.

A message with `reply_to` naming a running session there is typed into that session. Anything
else goes to that project's Product, started if none is running. A `to` that names no open
project is answered in the sender's own session.

## Why

Both sides of the read/prompt edge use this shape — [[read-project-messages]] reads it and
[[ask-other-projects-prompts]] tells agents to write it — so it is fixed here to let them run at
once. Like `blocks/` and `pages/` it is a channel to the app, not notebook content, so
`NotebookFormat.specText` does not list it. The app never writes these files; what it has
delivered it remembers itself.
