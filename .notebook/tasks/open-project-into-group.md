---
id: open-project-into-group
kind: task
title: "Open a project into a group"
status: done
depends_on: [new-project-in-group-design]
designer: ""
project: new-project-in-group
owner: ""
created: 2026-10-12
updated: 2026-10-12
external: {}
---

A group's context menu in the sidebar offers **New Project…**, and the project it creates lands
as that group's last member, so the group's projects stay adjacent. The model half is built; this
task is done when someone can do it from the sidebar, as the approved demo shows.

## Done when

- [x] `AppModel.open(_:into:)` adds the project carrying the group's name, inserted right after
      the group's last member. With no group, or a group no project carries, it appends at the
      end as `open(_:)` did.
- [x] Opening into the `pendingGroup` names the project with it and clears `pendingGroup`, so the
      empty group's placeholder is replaced by the real group.
- [x] `storedProjects` and `storedGroups` hold the new order and group, so a relaunch restores it.
- [x] Tests in `ProjectGroupTests` cover: into a group in the middle of the list, into the last
      group, into a pending group, and no group. The adjacency invariant holds in each.
- [x] A group header's context menu, and a pending empty group's, has **New Project…** as the
      demo shows. It opens the New Project sheet with the group named in it as designed.
- [x] Creating the project from that sheet adds it as the group's last member. In a pending
      group, it becomes that group's first member.
- [x] File > New Project… and the sidebar's + menu still open the sheet with no group, and the
      project lands loose at the end of the list, as today.
- [x] Cancelling the sheet leaves every group as it was.
- [x] Shots rendered before and after, with the differences in the sidebar and the sheet named.
      `make check` passes.

## Context

The first attempt built only the model, because this task was first written as model-only and
the screen was a task of its own. That left a task marked done with nothing to see, so the screen
was folded in here ([[2026-10-12-one-task-model-and-ui]]).

What is already there: `AppModel.open(_ directory: URL, into group: String? = nil)` and its tests
in `ProjectGroupTests`. What is left is sending the group from the sidebar to that call. The
sheet is shown from `model.creatingProject` (`RootView.swift`), and
`createProject(at:prompt:agent:)` in `RootView+Actions.swift` opens the folder, so the group has
to travel with the request to create. Takes the approved menu wording and the sheet's group line
from [[new-project-in-group-design]].

Area: `Sources/YongkangUI/Model/AppModel.swift`, `Sources/YongkangUI/App/ProjectSidebar+Groups.swift`,
`ProjectSidebar.swift`, `RootView.swift`, `RootView+Actions.swift`,
`Features/Home/NewProjectForm.swift`. A group is a name on its projects, never a container (see
`ProjectGroups`).
