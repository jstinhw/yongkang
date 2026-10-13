---
id: new-project-group-picker
kind: task
title: "Pick the group in New Project"
status: done
depends_on: [new-project-group-picker-design]
designer: ""
project: new-project-in-group
owner: ""
created: 2026-10-12
updated: 2026-10-13
external: {}
---

The New Project sheet lets someone choose which group the project joins, starting on no group
from the + menu and File > New Project…, and on the group it was opened from otherwise, as the
approved demo shows.

## Done when

- [x] The sheet shows the group control as the demo does, listing every group in sidebar order,
      the pending empty group if there is one, and no group.
- [x] Opened from the + menu or File > New Project…, it starts on no group, and creating without
      touching it lands the project loose at the end of the list, as today.
- [x] Opened from a group's **New Project…**, it starts on that group.
- [x] Picking a group and creating adds the project as that group's last member; picking the
      pending group makes it that group's first member.
- [x] With no groups at all, the sheet shows no control.
- [x] Cancelling leaves every group as it was, and reopening from the + menu starts on no group
      again, never the last choice.
- [x] Shots rendered before and after, with the differences in the sheet named. `make check`
      passes.

## Context

Takes the control's place, label and wording, and the title, from the approved demo of
[[new-project-group-picker-design]]. Decisions behind it: [[2026-10-12-group-picker-in-sheet]].

What is already there: `AppModel.newProject(in:)` sets `newProjectGroup` and opens the sheet;
`NewProjectForm` gets that as `group` and names it in the title; `createProject(at:prompt:agent:)`
in `RootView+Actions.swift` calls `AppModel.open(_:into:)` with `model.newProjectGroup`, which
already places the project at the end of a group's run, or fills `pendingGroup`. So the choice in
the sheet has to reach that `open` call, and the list of groups has to reach the sheet (group
names in `projects` order, plus `pendingGroup`).

Area: `Sources/YongkangUI/Features/Home/NewProjectForm.swift`, `Sources/YongkangUI/App/RootView.swift`,
`RootView+Actions.swift`, and `AppModel.swift` only if the group list needs a helper. A group is a
name on its projects, never a container (see `ProjectGroups`).
