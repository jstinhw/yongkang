---
id: sidebar-counts
kind: project
title: "Sidebar counts what it lists"
status: todo
depends_on: []
repos: [.]
roadmap: agent-team-console
owner: ""
created: 2026-10-12
updated: 2026-10-12
external: {}
---

The number next to a project in the sidebar matches the rows listed under it. Under Board, a
task held up by two open blocks is one task, and the project's count says 1.

## Outcome

In the Board section, a project's amber and green counts in the sidebar (and on a folded group's
header) count the task rows the sidebar lists under that project. In the Agents section they keep
counting what they count today.

## Done when

- [ ] [[board-sidebar-task-counts]] is done.

## Approach

The sidebar works out its counts in one place, `SidebarProject.needsYou`/`toReview`, from
`agentRows`, where each open block is a row of its own. Under Board it should count from `tasks`
(the `taskRows` it already lists). Fix it there, so the project row, the folded group header and
the accessibility summary all agree.

## Tasks

- [[board-sidebar-task-counts]]

## Decisions

- [[2026-10-12-board-counts-tasks]]
