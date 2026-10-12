---
id: new-project-in-group
kind: project
title: "New project in a group"
status: todo
depends_on: []
repos: [.]
roadmap: agent-team-console
owner: ""
created: 2026-10-12
updated: 2026-10-12
external: {}
---

Someone can start a new project straight inside one of their sidebar groups, instead of
creating it at the end of the list and dragging it in.

## Outcome

Right-clicking a group in the sidebar offers **New Project…**. It opens the usual New Project
sheet, which says which group the project will join, and the project it creates lands as that
group's last member. A group just named from the + menu, with nothing in it yet, offers the same.

## Done when

- [ ] [[new-project-in-group-design]] is approved.
- [ ] [[open-project-into-group]] and [[new-project-in-group-ui]] are done.

## Approach

A group is a name its projects carry, and its projects stay adjacent (`ProjectGroups`, guarded
by `ProjectGroupTests`). So creating a project in a group means opening it at the end of that
group's run with the group's name on it. That is a model change (`AppModel`), and a sidebar
and sheet change that sends the group through. The design comes first because the sheet and the
context menus change.

## Tasks

1. [[new-project-in-group-design]]: Allen
2. [[open-project-into-group]]: can start right away, alongside the design
3. [[new-project-in-group-ui]]: waits on 1, 2 and [[board-sidebar-task-counts]]

## Decisions

- [[2026-10-12-group-context-menu-entry]]
