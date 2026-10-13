---
id: new-project-in-group-design
kind: task
title: "Design new project in a group"
status: done
depends_on: []
designer: Allen
project: new-project-in-group
owner: ""
created: 2026-10-12
updated: 2026-10-12
external: {}
---

A demo of starting a new project from a sidebar group: where the entry is, what the New Project
sheet says about the group, and where the project lands.

## Done when

- [x] The demo shows a group header's context menu with **New Project…** beside Rename Group… and
      Ungroup, and the same on a pending empty group (the "Drag a project here" one).
- [x] The demo shows the New Project sheet opened from a group, saying which group the project will
      join, and the same sheet opened from File > New Project…, which names no group.
- [x] The demo shows the sidebar after creation: the new project as the group's last member,
      indented under its header, and a pending group becoming a real one with that project in it.
- [x] The user has approved the demo.

## Context

Mock it in Claude Code's native `/design` skill, never the gstack `design-*` skills. Today's
pieces: the group header and pending group in `Sources/YongkangUI/App/ProjectSidebar+Groups.swift`,
the + menu in `ProjectSidebar.swift`, the sheet in `Sources/YongkangUI/Features/Home/NewProjectForm.swift`.
The entry point is already decided ([[2026-10-12-group-context-menu-entry]]). The demo is how the
user checks that reading and settles how the sheet names the group.

What crosses to [[open-project-into-group]]: the approved menu wording, the sheet's group line,
and where it sits.
