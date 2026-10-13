---
kind: run
session: f3edc585-5a5e-4c6c-bcee-96320b96e653
task: board-sidebar-task-counts
work_id: board-sidebar-task-counts
title: "Board counts tasks, not blocks"
status: done
paths: [Sources/YongkangUI/App/ProjectSidebar.swift, Sources/YongkangUI/App/ProjectSidebar+Groups.swift, Tests/YongkangUITests/SidebarCountTests.swift, .notebook/tasks/board-sidebar-task-counts.md, .notebook/runs/f3edc585-5a5e-4c6c-bcee-96320b96e653-work-board-sidebar-task-counts.md]
report: "Under Board the sidebar's counts now count the task rows it lists; Agents is unchanged."
started_at: 2026-10-12T20:03:00+08:00
finished_at: 2026-10-12T20:14:00+08:00
---

## Result

`SidebarProject.needsYou`/`toReview` were properties counting `rows` (from `agentRows`, one row
per open block). They are now `needsYou(in:)`/`toReview(in:)`, counting
`counted(in: section)`: `tasks` under Board, `rows` under Agents. The three readers (the
project row's capsules, the folded group header's sums, and `summary(of:)`, the row's
accessibility label) pass the `section` the sidebar already has, so all three agree.
`agentRows`, `taskRows` and the Board's "Waiting on you" inspector are untouched.

On screen: in every Board-section shot, the amber capsule beside `yongkang` reads **2** instead
of **3**. Two amber task rows are listed under it ("Design the task page's diff", "Deploy to
Vercel"). The green 1 and the grouped neighbours (`notebook-sync` ✓1, `yongkang-site` •1) are
unchanged. All Agents-section shots (`agents*.png`, `session*.png` other than below) are byte
identical before and after.

## Verification

- `swift test --filter SidebarCountTests` passed: one task, two open blocks, no session gives
  `needsYou(in: .board) == 1` and `needsYou(in: .agents) == 2`.
- With `counted(in:)` temporarily made to return `rows` (the old behaviour), the same test fails:
  `Expectation failed: (item.needsYou(in: .board) → 2) == 1`. Restored afterwards.
- `make check` exited 0: `swift format lint --strict` clean, and `Test run with 459 tests in 67
  suites passed ... with 12 known issues` (the existing `withKnownIssue`s, none new).
- `swift run shots` into `before/` (pre-change) and `after/` in this session's scratchpad, then a
  pixel diff of each PNG:
  - `board*.png`, `demo*.png`, `setup-*.png`, `task.png`: 96 px changed, all inside the one
    11×16 px box of the project's amber count digit (3 → 2).
  - `review.png`, `session-command.png`, `skills.png`: also differ between two renders of the
    same code (`after/` vs `after2/`), so they are noise, not this change.
  - `usage.png` reads this Mac's live sessions. A "Plan" row under one live session was there
    before and gone after, because that session's drawn page changed in between. Its counts are
    the same on both sides.

## Review

```json
{
  "summary": "Under Board, a project's sidebar counts, folded group sums and accessibility label count the task rows listed, not open blocks.",
  "confidence": "high",
  "confidence_why": "One source for all three readers; test fails on the old code.",
  "touches": "sidebar project counts",
  "changed": [
    "Board: yongkang's amber count reads 2 beside its two amber rows, was 3",
    "A task with two open blocks counts 1 under Board, 2 under Agents"
  ],
  "checks": [
    {"claim": "Board counts tasks once", "status": "passed", "result": "aTaskHeldUpByTwoBlocksCountsOnceUnderBoard passed",
     "command": "swift test --filter SidebarCountTests → ✔ Test run with 1 test in 1 suite passed"},
    {"claim": "Test catches the old bug", "status": "passed", "result": "old counting: needsYou(in: .board) → 2, expected 1",
     "command": "counted(in:) set to rows, swift test --filter SidebarCountTests → ✘ (item.needsYou(in: .board) → 2) == 1"},
    {"claim": "Lint, build, all tests", "status": "passed", "result": "459 tests passed, 12 known issues, exit 0",
     "command": "make check → exit 0; Test run with 459 tests in 67 suites passed with 12 known issues"},
    {"claim": "Only Board's count digit changed", "status": "passed", "result": "96 px in the count digit; Agents shots identical",
     "command": "swift run shots before/ and after/, pixel diff per PNG → board/demo/setup/task differ only at the count"}
  ],
  "holds": [
    "Each section counts the same array it lists under the project, so count and rows cannot drift."
  ],
  "spots": [
    {"path": "Sources/YongkangUI/App/ProjectSidebar+Groups.swift", "lines": [55, 60],
     "label": "folded header", "why": "No shot folds a group, so the Board sum here is checked by reading only."}
  ],
  "questions": [],
  "concerns": [
    {"title": "Another session shares this checkout",
     "detail": "AppModel.swift and ProjectGroupTests.swift changed under me (open-project-into-group). Not mine; make check passed with them in the tree.",
     "blocks": false}
  ],
  "outside": [
    {"kind": "local", "what": "Rendered shots, crops and a pixel-diff tool into this session's scratchpad"}
  ],
  "files": [
    {"path": "Sources/YongkangUI/App/ProjectSidebar.swift", "why": "Counts read the section's rows; row and label use it"},
    {"path": "Sources/YongkangUI/App/ProjectSidebar+Groups.swift", "why": "Folded header sums by section"},
    {"path": "Tests/YongkangUITests/SidebarCountTests.swift", "why": "One task, two blocks: Board 1, Agents 2"},
    {"path": ".notebook/tasks/board-sidebar-task-counts.md", "why": "Status done, Done when checked"},
    {"path": ".notebook/runs/f3edc585-5a5e-4c6c-bcee-96320b96e653-work-board-sidebar-task-counts.md", "why": "This report"}
  ],
  "next": "Closes the sidebar-counts project; its one task is done."
}
```
