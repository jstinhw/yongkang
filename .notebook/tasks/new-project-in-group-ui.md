---
id: new-project-in-group-ui
kind: task
title: "New Project on a group"
status: todo
depends_on: [new-project-in-group-design, open-project-into-group, board-sidebar-task-counts]
designer: ""
project: new-project-in-group
owner: ""
created: 2026-10-12
updated: 2026-10-12
external: {}
---

A group's context menu in the sidebar offers New Project…, and the project it creates lands in
that group, as the approved demo shows.

## Done when

- [ ] A group header's context menu, and a pending empty group's, has **New Project…** as the
      demo shows. It opens the New Project sheet with the group named in it as designed.
- [ ] Creating the project from that sheet adds it as the group's last member. In a pending
      group, it becomes that group's first member.
- [ ] File > New Project… and the sidebar's + menu still open the sheet with no group, and the
      project lands loose at the end of the list, as today.
- [ ] Cancelling the sheet leaves every group as it was.
- [ ] Shots rendered before and after, with the differences in the sidebar and the sheet named.
      `make check` passes.

## Context

Takes the approved design from [[new-project-in-group-design]] and `AppModel.open(_:into:)` from
[[open-project-into-group]]. The sheet is shown from `model.creatingProject`
(`RootView.swift`), and `createProject(at:prompt:agent:)` in `RootView+Actions.swift` opens the
folder. The group has to travel with the request to create and reach that `open` call.

Area: `Sources/YongkangUI/App/ProjectSidebar+Groups.swift`, `RootView.swift`,
`RootView+Actions.swift`, `Features/Home/NewProjectForm.swift`. It waits on
[[board-sidebar-task-counts]] only because that task may change the group header in the same file.
