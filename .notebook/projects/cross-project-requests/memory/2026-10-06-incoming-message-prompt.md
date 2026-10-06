---
id: incoming-message-prompt
kind: memory
title: "Incoming message prompt"
project: cross-project-requests
subject: deliver-project-messages
memory_type: decision
source: agent
supersedes: []
created: 2026-10-06
updated: 2026-10-06
external: {}
---

The text the app types into the receiving session is
`NotebookFormat.incomingMessage(from:session:title:body:)`: `from` is the sender's folder
relative to the receiver's, `session` the sending session's id, then the message's title and
body. It ends with how to answer, `to` and `reply_to` filled in.

A first message goes to the receiving project's Product as
`startProduct("asked\n" + incomingMessage(...), agent:, reading: [sender's folder])`: `asked`
is the Product skill's mode for it. A reply is typed into the session its `reply_to` names as it
is, with no mode line.

## Why

The function takes plain strings so it waits on nothing from [[read-project-messages]]; the
mode line stays with the caller because only a first message goes to Product. Passing the
sender's folder as `reading` lets that Product read it and tells it to ask, not write, there.
