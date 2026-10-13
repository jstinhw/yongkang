---
id: board-sidebar-task-counts
kind: task
title: "Count tasks under Board"
status: done
depends_on: []
designer: ""
project: sidebar-counts
owner: ""
created: 2026-10-12
updated: 2026-10-12
external: {}
---

Under Board, a project's sidebar count says how many of its listed tasks need you, not how many
open blocks it has. Today one task holding two blocks shows a count of 2 beside one row.

## Done when

- [x] In the Board section, the amber count beside a project in the sidebar equals the number of
      task rows under it in the `.needsYou` state, and the green count equals those in `.review`.
      A task with two open blocks counts once.
- [x] A folded group's header under Board sums the same per-project task counts.
- [x] The project row's accessibility summary ("N need you, M to review") uses the same numbers
      as the count it sits beside.
- [x] Under Agents, the counts are unchanged.
- [x] A test builds a project with one task and two open blocks on it, and checks that its Board
      count is 1 while its Agents count stays as it is today; `make check` passes.

## Context

Seen on this repo: `first-release` has two open blocks, `tag-v0-1-0` and `release-secrets`. The
sidebar lists one task under Yongkang but shows 2.

The cause: `SidebarProject.needsYou` and `toReview` (`Sources/YongkangUI/App/ProjectSidebar.swift`)
count `rows`, which comes from `agentRows` (`Sources/YongkangCore/Project/AgentRow.swift`).
`agentRows` gives every open block that no session has claimed a row of its own (`block:<id>`).
Under Board the sidebar lists `tasks`, which comes from `taskRows`, one per task. The counts are
also read by the folded group header (`ProjectSidebar+Groups.swift`) and `summary(of:)`. Fix it
where they all read from, using the `section` the sidebar already has, not in each caller.

Area: the sidebar in `Sources/YongkangUI/App/`. Leave `agentRows`, `taskRows` and the Board's
"Waiting on you" inspector alone: the inspector lists blocks on purpose (see
[[2026-10-12-board-counts-tasks]]).

## Constraints

A UI change: render shots before and after and say what changed in the sidebar.
