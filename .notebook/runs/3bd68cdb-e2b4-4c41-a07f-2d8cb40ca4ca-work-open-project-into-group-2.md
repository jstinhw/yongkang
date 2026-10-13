---
kind: run
session: 3bd68cdb-e2b4-4c41-a07f-2d8cb40ca4ca
task: open-project-into-group
work_id: open-project-into-group-2
title: "New Project… on a sidebar group"
status: done
paths: [Sources/YongkangUI/Model/AppModel.swift, Sources/YongkangUI/App/Commands.swift, Sources/YongkangUI/App/RootView.swift, Sources/YongkangUI/App/RootView+Actions.swift, Sources/YongkangUI/App/ProjectSidebar.swift, Sources/YongkangUI/App/ProjectSidebar+Groups.swift, Sources/YongkangUI/Features/Home/NewProjectForm.swift, Sources/Shots/DesignShots.swift, Tests/YongkangUITests/ProjectGroupTests.swift, .notebook/tasks/open-project-into-group.md, .notebook/runs/3bd68cdb-e2b4-4c41-a07f-2d8cb40ca4ca-work-open-project-into-group-2.md]
report: "A group's menu starts a project in it; the sheet names the group."
started_at: 2026-10-12T12:24:46Z
finished_at: 2026-10-12T12:31:00Z
---

## Result

This is the screen half of the task, built as the approved demo v1 shows. The model half
(`AppModel.open(_:into:)` and its four tests) was already in the tree from the first attempt.

- **The menu.** Right-clicking a group's header gives **New Project…**, then a divider, then
  Rename Group… and Ungroup. A group named from the + menu with nothing in it yet has the same
  menu on its header and on its dashed "Drag a project here" row. All three use one menu,
  `groupMenu(_:)` in `ProjectSidebar+Groups.swift`.
- **The sheet.** Opened from a group, the title reads "New project in Client work", with the group
  name in `Theme.tx2`. A long name is cut short and the agent picker stays whole. Opened from
  File › New Project…, the sidebar's + menu or the empty screen, the sheet is unchanged.
- **Where it lands.** `createProject` opens the folder with `open(directory, into:
  model.newProjectGroup)`. The project becomes the group's last member, or the first member of a
  group that was empty, which then becomes a real group.
- **How the group travels.** `AppModel.newProject(in:)` sets `newProjectGroup` and opens the sheet,
  and every way of opening the sheet now goes through it. So the File menu's sheet always has no
  group, whatever the last sheet had. Cancel leaves every group as it was, the empty one included.

`ProjectSidebar` takes `createIn` with a default that does nothing, so the shots' sidebar needed
no change. `DesignShots.swift` gains a `new-project-group` shot.

## Verification

- `swift test --filter ProjectGroupTests`: "Test run with 16 tests in 1 suite passed". Two of them
  are new. One opens a sheet from a group, then one from the File menu, and the projects land
  `["a", "e", "b", "f"]` with groups `["One", "One", nil, nil]`. The other cancels a sheet from an
  empty group and checks the group is still pending.
- `make check`: "Test run with 462 tests in 67 suites passed after 9.016 seconds with 12 known
  issues". The 12 known issues are `withKnownIssue`s already in the suite, none of them mine.
- Shots, before (42 files) and after (43). `new-project-group.png` is new and shows "New project in
  Client work". `new-project.png` and every sidebar shot are byte-identical. Three files differ for
  reasons that aren't this change: `review.png` and `session-command.png` read the clock ("written
  8:26 PM" vs "8:28 PM"), and `plan.html` has the same JSON with its keys in another order.
- A one-off render with the group "Client work for the agency we took on in the spring" read "New
  project in Client work for the agency we…" beside a whole Claude Code picker. I reverted it
  afterwards; the shot keeps "Client work".
- Not run: the context menus in the running app. Shots can't draw a context menu, and I didn't
  launch the app because your copy is running. The smoke check is to right-click a group's header,
  and an empty group's dashed row, and look for New Project… at the top.

## Review

```json
{
  "summary": "A sidebar group's menu now offers New Project…, the sheet names the group, and the project lands as its last member.",
  "confidence": "high",
  "confidence_why": "Model tests cover landing; shots show the sheet; full suite passes.",
  "touches": "Sidebar, sheet, AppModel",
  "changed": [
    "Right-clicking a group offers New Project… above Rename Group… and Ungroup",
    "The sheet from a group reads New project in <group>",
    "The created project lands as that group's last member",
    "File › New Project… and + still make a loose project"
  ],
  "checks": [
    {"claim": "Projects land in their group", "status": "passed", "result": "16 tests in 1 suite passed",
     "command": "swift test --filter ProjectGroupTests → Test run with 16 tests in 1 suite passed"},
    {"claim": "Lint, build and tests pass", "status": "passed", "result": "462 tests passed, 12 known issues",
     "command": "make check → Test run with 462 tests in 67 suites passed after 9.016 seconds with 12 known issues"},
    {"claim": "Only the group sheet changed", "status": "passed", "result": "new-project-group.png new; other diffs are the clock",
     "command": "swift run shots before/ and after/, cmp each file → new: new-project-group.png; differs: review.png, session-command.png, plan.html"},
    {"claim": "Long group name truncates", "status": "passed", "result": "name cut with …, picker whole",
     "command": "swift run shots with a long group name → New project in Client work for the agency we…"},
    {"claim": "Menu seen in the app", "status": "not_run", "result": "app not launched; your copy is running",
     "command": "right-click a group header in Yongkang"}
  ],
  "holds": [
    "Every way of opening the sheet sets its group, so a stale group can't leak.",
    "A group gone while the sheet was up leaves the project loose, never revived."
  ],
  "shows": [
    {"kind": "ui", "title": "Sheet opened from a group",
     "after": "file:///private/tmp/claude-501/-Users-justinzen-Desktop-justin-justinzen-sources-projects-yongkang/3bd68cdb-e2b4-4c41-a07f-2d8cb40ca4ca/scratchpad/ui-after/new-project-group.png",
     "serve_after": "swift run shots /tmp/shots && open /tmp/shots/new-project-group.png",
     "note": "A native app, so a shot instead of a served page; context menus never appear in shots."},
    {"kind": "api", "title": "Opening the new-project sheet",
     "before": "model.creatingProject = true",
     "after": "model.newProject(in: group)  // sets newProjectGroup, then creatingProject",
     "test": "ProjectGroupTests/theSheetFromAGroupJoinsItAndTheNextFromTheFileMenuDoesNot"}
  ],
  "spots": [
    {"path": "Sources/YongkangUI/App/ProjectSidebar+Groups.swift", "lines": [96, 119], "label": "Dashed row menu",
     "why": "The approved demo also gave the empty group's dashed row the menu; it's the one place beyond the task's wording."},
    {"path": "Sources/YongkangUI/App/ProjectSidebar.swift", "lines": [135, 136], "label": "createIn default",
     "why": "Defaults to doing nothing so the shots' sidebar compiles unchanged; RootView passes the real one."},
    {"path": "Sources/YongkangUI/Features/Home/NewProjectForm.swift", "lines": [103, 112], "label": "Sheet title",
     "why": "The picker is fixedSize so a long group name truncates instead; checked once with a long name."}
  ],
  "questions": [],
  "concerns": [
    {"title": "Menus not seen running",
     "detail": "Shots can't draw context menus and I didn't launch your app. Right-click a group once to confirm.",
     "blocks": false},
    {"title": "DesignShots has another session's edit",
     "detail": "Removing the demo-artifact shot there isn't mine. My hunk is only the new-project-group shot.",
     "blocks": false}
  ],
  "outside": [
    {"kind": "local", "what": "Rendered before, after and long-name shots into the session scratchpad"}
  ],
  "files": [
    {"path": "Sources/YongkangUI/Model/AppModel.swift", "why": "newProject(in:) carries the sheet's group"},
    {"path": "Sources/YongkangUI/App/Commands.swift", "why": "File menu opens the sheet with no group"},
    {"path": "Sources/YongkangUI/App/RootView.swift", "why": "Every opener goes through newProject(in:)"},
    {"path": "Sources/YongkangUI/App/RootView+Actions.swift", "why": "Created project opens into the sheet's group"},
    {"path": "Sources/YongkangUI/App/ProjectSidebar.swift", "why": "Takes createIn from the window"},
    {"path": "Sources/YongkangUI/App/ProjectSidebar+Groups.swift", "why": "One group menu, New Project… first"},
    {"path": "Sources/YongkangUI/Features/Home/NewProjectForm.swift", "why": "Title names the group"},
    {"path": "Sources/Shots/DesignShots.swift", "why": "new-project-group shot"},
    {"path": "Tests/YongkangUITests/ProjectGroupTests.swift", "why": "File menu sheet and cancel tests"},
    {"path": ".notebook/tasks/open-project-into-group.md", "why": "Done when ticked, status done"},
    {"path": ".notebook/runs/3bd68cdb-e2b4-4c41-a07f-2d8cb40ca4ca-work-open-project-into-group-2.md", "why": "This report"}
  ],
  "next": "Meets the New project in a group project's Done when."
}
```
