---
kind: run
session: a8002a11-216a-4219-868e-b71818d4dc46
task: new-project-group-picker
work_id: new-project-group-picker
title: "Group button in the New Project sheet"
status: done
paths: [Sources/YongkangUI/Features/Home/NewProjectForm.swift, Sources/YongkangUI/Model/AppModel.swift, Sources/YongkangUI/App/RootView.swift, Sources/Shots/DesignShots.swift, Tests/YongkangUITests/ProjectGroupTests.swift, .notebook/tasks/new-project-group-picker.md, .notebook/runs/a8002a11-216a-4219-868e-b71818d4dc46-work-new-project-group-picker.md]
report: "The New Project sheet has a group button beside the agent picker, as in the approved demo; make check passes."
started_at: 2026-10-13T12:04:57Z
finished_at: 2026-10-13T12:12:00Z
---

## Result

The New Project sheet's title row now has a group button, left of the agent picker and drawn
the same way: a stack icon, the group's name, the up-down chevrons. This is the approved demo.

- **From the + menu or File › New Project…** the button reads **No group**. Creating without
  touching it opens the project loose at the end of the list, as before.
- **From a group's New Project…** it starts on that group.
- **The title** is "New project" however the sheet opens. The old "New project in Client work"
  is gone, because the button names the group in the same row.
- **Clicking the button** opens a plain menu: No group, a divider, then every group in sidebar
  order, with a group still waiting for its first project last. The current choice has a tick.
- **With no groups at all** there's no button, and the sheet is pixel-identical to before.
- **A long group name** is cut short in the button. The title and the agent picker stay whole.
- VoiceOver reads it as "Group for this project", with the group's name as the value.

How the pick gets through: the button is bound to `AppModel.newProjectGroup`, which is no
longer `private(set)`. `createProject` already passes that to `open(_:into:)`, so
`RootView+Actions.swift` didn't change. `newProject(in:)` still resets it every time the sheet
opens, so a cancelled pick never carries over to the next sheet. The list comes from a new
`AppModel.groupNames`: each group's name in project order, then `pendingGroup`, each name once.

Shots: the two `NewProjectForm` shots are now one loop over three cases. It adds
`new-project-loose.png`, the + menu's sheet with groups to pick from, and `DesignShots.swift`
stays at 796 lines.

Differences in the sheet, before → after:

- `new-project.png` (no groups): no difference, byte-identical.
- `new-project-group.png` (from Client work): the title changes from "New project in Client
  work" to "New project", and a **Client work** button appears left of Claude Code.
- `new-project-loose.png` (new, from the + menu with groups): a **No group** button left of
  Claude Code. Before this change, that sheet looked like `new-project.png`.
- Other shots: `handover`, `review` and `usage` changed because they read git or the clock.
  `session-command` changed only in its "written 8:05 PM" time stamp. Nothing else changed.

## Verification

- `swift run shots <scratchpad>/before`, from a `git archive HEAD` copy at 9e888eb in the
  session scratchpad, printed "shots written to …/before".
- `swift run shots <scratchpad>/after`, from this working tree, printed "shots written to
  …/after".
- `cmp` of every shot pair, before against after:
  - `new-project.png` is identical.
  - These differ: `handover.png`, `new-project-group.png`, `review.png`,
    `session-command.png`, `usage.png`.
  - `new-project-loose.png` is new.
  - A pixel bounding box on `session-command.png` put the change at x 2780–2822, y 1326–1342.
    The crops show "written 8:05 PM" against "written 8:08 PM".
- Long name: a temporary edit gave the from-a-group shot the name "Client work for the agency
  we took on in the spring", and the shots were rendered to `<scratchpad>/long`. The button
  read "Client work for the agency we…", and the title and Claude Code were whole. The edit was
  reverted: `grep -c agency Sources/Shots/DesignShots.swift` prints 0.
- `swift test --filter ProjectGroupTests` printed "Test run with 18 tests in 1 suite passed",
  including the two new tests:
  - `theSheetOffersEveryGroupInSidebarOrderWithTheEmptyOneLast`: with no groups the list is
    empty. Otherwise it is in sidebar order with the pending group last, and a pending name a
    run already has is listed once.
  - `aGroupPickedInTheSheetIsWhereTheProjectLandsAndCancelForgetsIt`: a pick then Cancel
    leaves the groups as they were, and the next + menu sheet starts on nil. A pick of "One"
    lands as One's last member. A pick of the pending group lands as its first member, and
    `pendingGroup` empties.
- `make check` (lint, build, test) printed "Test run with 466 tests in 67 suites passed … with
  12 known issues". `swift format lint --strict -r Sources Tests` exited 0. The same 12 known
  issues are there at HEAD: `swift test` in the archive copy printed "463 tests … passed … with
  12 known issues".
- Not run: the open menu itself, meaning the tick and the divider between No group and the
  groups. An offscreen shot can't open a menu, and I didn't launch the app because your copy is
  running. The menu is a `Picker` inside a `Menu`, with `.menuStyle(.button)` and the console
  button style. The Skills page's "Shared skills" menu uses the same style.

## Review

```json
{
  "summary": "The New Project sheet gets a group button beside the agent picker, starting on No group or the group it opened from.",
  "confidence": "high",
  "confidence_why": "Model paths tested; shots match the demo; menu not opened live.",
  "touches": "New Project sheet",
  "changed": [
    "A No group button sits left of the agent picker when groups exist",
    "Opened from a group, the button starts on that group",
    "The title reads New project, no longer New project in <group>",
    "With no groups the sheet is pixel-identical to before"
  ],
  "checks": [
    {"claim": "Group order and pick land", "status": "passed", "result": "18 tests in 1 suite passed",
     "command": "swift test --filter ProjectGroupTests → Test run with 18 tests in 1 suite passed"},
    {"claim": "Lint, build and tests pass", "status": "passed", "result": "466 tests passed, 12 known issues as at HEAD",
     "command": "make check → Test run with 466 tests in 67 suites passed after 10.610 seconds with 12 known issues"},
    {"claim": "No-groups sheet unchanged", "status": "passed", "result": "new-project.png byte-identical",
     "command": "cmp before/new-project.png after/new-project.png → (no output, exit 0)"},
    {"claim": "Long name truncates, picker whole", "status": "passed", "result": "Client work for the agency we…",
     "command": "swift run shots <scratchpad>/long with a temporary long name, reverted"},
    {"claim": "Menu shows tick and divider", "status": "not_run", "result": "shots cannot open a menu; app not launched",
     "command": "make run, then File › New Project… (not run: your copy is running)"}
  ],
  "holds": [
    "newProject(in:) resets the group on every open, so a cancelled pick never carries over.",
    "open(_:into:) already ignores a group that vanished while the sheet was up."
  ],
  "shows": [
    {"kind": "ui", "title": "Sheet from the + menu",
     "before": "/private/tmp/claude-501/-Users-justinzen-Desktop-justin-justinzen-sources-projects-yongkang/a8002a11-216a-4219-868e-b71818d4dc46/scratchpad/before/new-project.png",
     "after": "/private/tmp/claude-501/-Users-justinzen-Desktop-justin-justinzen-sources-projects-yongkang/a8002a11-216a-4219-868e-b71818d4dc46/scratchpad/after/new-project-loose.png",
     "note": "Before, the + menu sheet looked the same with or without groups, so new-project.png stands in."},
    {"kind": "ui", "title": "Sheet from a group",
     "before": "/private/tmp/claude-501/-Users-justinzen-Desktop-justin-justinzen-sources-projects-yongkang/a8002a11-216a-4219-868e-b71818d4dc46/scratchpad/before/new-project-group.png",
     "after": "/private/tmp/claude-501/-Users-justinzen-Desktop-justin-justinzen-sources-projects-yongkang/a8002a11-216a-4219-868e-b71818d4dc46/scratchpad/after/new-project-group.png",
     "note": "The title drops the group name, as the approved demo says."}
  ],
  "spots": [
    {"path": "Sources/YongkangUI/Features/Home/NewProjectForm.swift", "lines": [157, 182],
     "label": "group menu", "why": "The open menu, its tick and divider, is the one part no shot or test draws."},
    {"path": "Sources/YongkangUI/Model/AppModel.swift", "lines": [279, 284],
     "label": "groupNames", "why": "Builds the list the menu offers: run names in order, then the pending group."}
  ],
  "questions": [],
  "concerns": [
    {"title": "Open menu not seen live",
     "detail": "No group, divider, groups, tick: SwiftUI builds it from an inline Picker; a shot can't open it. Worth one click in the app.",
     "blocks": false}
  ],
  "outside": [
    {"kind": "local", "what": "Copied HEAD with git archive into the session scratchpad and built and tested it there"},
    {"kind": "local", "what": "Rendered before, after and long-name shots and diff crops into the session scratchpad"}
  ],
  "files": [
    {"path": "Sources/YongkangUI/Features/Home/NewProjectForm.swift", "why": "The group button; the title drops the group"},
    {"path": "Sources/YongkangUI/Model/AppModel.swift", "why": "groupNames; the sheet may set newProjectGroup"},
    {"path": "Sources/YongkangUI/App/RootView.swift", "why": "Passes the binding and the group list"},
    {"path": "Sources/Shots/DesignShots.swift", "why": "Three sheet shots, one of them new"},
    {"path": "Tests/YongkangUITests/ProjectGroupTests.swift", "why": "Group order, pick, cancel and reopen"},
    {"path": ".notebook/tasks/new-project-group-picker.md", "why": "Status done"},
    {"path": ".notebook/runs/a8002a11-216a-4219-868e-b71818d4dc46-work-new-project-group-picker.md", "why": "This report"}
  ],
  "next": "Finishes new-project-in-group's last task; the project can close."
}
```
