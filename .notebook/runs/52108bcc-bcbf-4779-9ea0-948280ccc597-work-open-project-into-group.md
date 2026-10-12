---
kind: run
session: 52108bcc-bcbf-4779-9ea0-948280ccc597
task: open-project-into-group
work_id: open-project-into-group
title: "Open a project into a group"
status: done
paths: [Sources/YongkangUI/Model/AppModel.swift, Tests/YongkangUITests/ProjectGroupTests.swift, .notebook/tasks/open-project-into-group.md]
report: "AppModel.open(_:into:) places a project after its group's last member, or fills the pending group."
started_at: 2026-10-12T12:08:14Z
finished_at: 2026-10-12T12:10:25Z
---

## Result

- `AppModel.open(_ directory: URL, into group: String? = nil)` replaces `open(_:)`. The two
  existing callers (`RootView+Actions.swift`: `openProject`, `createProject`) still call
  `open(directory)` and work exactly as before.
- With a group some project carries, the new project gets that name and goes right after the
  group's last member, so the group stays in one piece.
- With the `pendingGroup` (named from the + menu, nothing in it yet), the project gets that name,
  goes at the end where the placeholder was drawn, and `pendingGroup` is cleared.
- With no group, or a name nothing carries and that isn't pending (say the group was ungrouped
  while the sheet was open), the project goes at the end with no group. A group the user let go
  doesn't come back.
- `storedProjects` and `storedGroups` are read off `projects`, so they hold the new order and
  group without any extra code. A test restores from them to prove it.
- Nothing on screen changes: the sidebar and the sheet aren't touched, and they're
  [[new-project-in-group-ui]]'s job. So I rendered no shots.
- For [[new-project-in-group-ui]]: the signature is `open(_:into:)`. Pass the group's current
  name, or `model.pendingGroup` for the empty one.

## Verification

- `swift test --filter ProjectGroupTests`: `Test run with 14 tests in 1 suite passed` (10 old, 4 new).
- `make check`: exit 0. `swift format lint --strict` clean, `swift build` clean,
  `Test run with 459 tests in 67 suites passed after 9.159 seconds with 12 known issues`. The 12
  known issues are existing `withKnownIssue`s, none of them in `ProjectGroupTests`.
- The new tests: into a group in the middle (`a b e c d`, plus a relaunch round-trip), into the
  last group (`a b c e`), into the pending group (placeholder replaced, `pendingGroup == nil`,
  group stored), and no group or a gone group (both loose at the end). Each one checks
  `adjacent(model)`: once a group's run ends, its name never shows up again.
- While this ran, `Sources/YongkangUI/App/ProjectSidebar.swift` and
  `ProjectSidebar+Groups.swift` had uncommitted edits I didn't make, most likely the
  [[board-sidebar-task-counts]] work. I left them alone, and they're not in `paths`. They were in
  the tree when `make check` passed.

## Review
```json
{
  "summary": "AppModel.open now takes an optional group: the project lands after that group's last member, or fills the pending empty group.",
  "confidence": "high",
  "confidence_why": "Small model change; four new tests and make check pass.",
  "touches": "AppModel project order",
  "changed": [
    "open(_:into:) puts a project right after its group's last member",
    "Opening into the pending group names it and clears the placeholder",
    "No group, or a gone group, appends the project loose as before"
  ],
  "checks": [
    {"claim": "Open into group works", "status": "passed", "result": "14 tests in 1 suite passed", "command": "swift test --filter ProjectGroupTests → Test run with 14 tests in 1 suite passed"},
    {"claim": "Lint, build, all tests", "status": "passed", "result": "459 tests passed, 12 existing known issues", "command": "make check → exit 0; Test run with 459 tests in 67 suites passed with 12 known issues"},
    {"claim": "Screens unchanged", "status": "not_run", "result": "No view touched, so no shots", "command": "swift run shots: not run, model-only change"}
  ],
  "holds": [
    "The new parameter defaults to nil, so both existing callers keep today's append behaviour.",
    "Order and groups are saved from projects itself, so a relaunch can't disagree with the sidebar."
  ],
  "shows": [
    {"kind": "api", "title": "open gains an optional group",
     "before": "func open(_ directory: URL) -> ProjectModel",
     "after": "func open(_ directory: URL, into group: String? = nil) -> ProjectModel",
     "note": "An unknown, non-pending group leaves the project loose rather than starting the group again."}
  ],
  "spots": [
    {"path": "Sources/YongkangUI/Model/AppModel.swift", "lines": [227, 242], "label": "open(_:into:)", "why": "The whole change: where the project goes and when the pending group clears."},
    {"path": "Tests/YongkangUITests/ProjectGroupTests.swift", "lines": [25, 30], "label": "adjacency check", "why": "Every new test relies on this one-liner to prove groups stay in one piece."}
  ],
  "questions": [],
  "concerns": [
    {"title": "Sidebar files edited by someone else", "detail": "ProjectSidebar.swift and +Groups.swift have uncommitted edits that aren't mine, likely board-sidebar-task-counts. Commit them separately from this task.", "blocks": false}
  ],
  "outside": [],
  "files": [
    {"path": "Sources/YongkangUI/Model/AppModel.swift", "why": "open takes an optional group"},
    {"path": "Tests/YongkangUITests/ProjectGroupTests.swift", "why": "Four open-into-group tests, adjacency check"},
    {"path": ".notebook/tasks/open-project-into-group.md", "why": "Status done, Done when ticked"}
  ],
  "next": "new-project-in-group-ui can pass the group through to open"
}
```
