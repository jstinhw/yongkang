---
id: cross-project-request-design
kind: task
title: "Design a cross-project request"
status: todo
depends_on: []
designer: Allen
project: cross-project-requests
owner: ""
created: 2026-10-01
updated: 2026-10-01
external: {}
---

A demo of a request that spans two open projects, so the user can see who is talking to whom
before any SwiftUI is written.

## Done when

- [ ] The demo shows two projects in the sidebar and a request typed on the first one's board
      that tags the second.
- [ ] The first board while its Product waits on the other project's answer: the request banner
      says it is waiting on that project by name.
- [ ] The second project's sidebar with the Product session the message opened, saying which
      project asked.
- [ ] The second board with what its Product filed marked new, and a banner that names the asking
      project, with Open session, Ask for changes and Approve and commit.
- [ ] The first board once the answer is back and its own part is filed.
- [ ] The user approved the demo.

## Context

Surfaces that exist and stay: the sidebar's session rows, the board's `RequestBanner`, the
terminals. This adds who-is-talking-to-whom to them, not a new screen; the conversation itself
is read in each session's terminal. Design in Claude Code's `/design` canvas, per `AGENTS.md`.
What crosses into [[cross-project-request-ui]]: the approved demo.
