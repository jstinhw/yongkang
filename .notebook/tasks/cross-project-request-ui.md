---
id: cross-project-request-ui
kind: task
title: "Show who is talking"
status: done
depends_on: [cross-project-request-design, deliver-project-messages]
designer: ""
project: cross-project-requests
owner: ""
created: 2026-10-01
updated: 2026-10-06
external: {}
---

The sidebar and the board say which project a request came from and which project a session is
waiting on, as the approved demo shows.

## Done when

- [x] Every surface in the approved [[cross-project-request-design]] demo is built as it shows:
      the waiting banner on the asking board, the session row and request banner on the other.
- [x] Shots rendered before and after; the handoff says what changed on screen.
- [x] The smoke script in `docs/development.md` gains the two-project request.
- [x] `make check` passes.

## Context

Takes the approved demo from [[cross-project-request-design]], and from
[[deliver-project-messages]] what the model exposes: who asked a request, and which sessions are
waiting on another project. Area: `Features/Board/RequestBanner.swift`, the board that hosts it,
and the session rows in `App/ProjectSidebar.swift`. Sample data for the shots goes in
`Sources/Shots/`.
