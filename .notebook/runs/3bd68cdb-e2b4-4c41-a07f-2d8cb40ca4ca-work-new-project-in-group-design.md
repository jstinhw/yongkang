---
kind: run
session: 3bd68cdb-e2b4-4c41-a07f-2d8cb40ca4ca
task: new-project-in-group-design
work_id: new-project-in-group-design
title: "Design new project in a group"
status: done
paths: [.notebook/tasks/new-project-in-group-design.md, .notebook/blocks/new-project-in-group-design-demo.md, .notebook/runs/3bd68cdb-e2b4-4c41-a07f-2d8cb40ca4ca-work-new-project-in-group-design.md]
report: "Six-frame demo published and approved; task done."
started_at: 2026-10-12T12:08:00Z
finished_at: 2026-10-12T12:19:00Z
---

## Result

The demo is at https://claude.ai/artifact/TgZ4tim2CrmoJqdHAwiv7H. It's one page with six frames, each
a 1440×900 window cropped to the part that changes. A switch shows the whole window, and the
changes are outlined in pink while "Outline what's new" is on (the default). Every frame is a real
shot from `swift run shots` with only the change drawn over it.

1. **Where it starts.** Right-clicking the Client work header opens a menu with **New Project…** first,
   then a divider, then Rename Group… and Ungroup. "Side projects", a group just named from the +
   menu with nothing in it yet, has the same menu on its header and on its dashed "Drag a project
   here" row. The row's wording doesn't change.
2. **The sheet.** Opened from a group, the title reads "New project in Client work". The group's name
   is in the dimmer ink the sidebar draws group names in. Opened from File › New Project…, it's the
   sheet as it is today: "New project", with no group.
3. **Where it lands.** weather-cli is Client work's last member, indented under its header, with the
   group counting 3. It opens on its notebook setup, as a new project does today. In the empty group,
   Side projects becomes a real group with weather-cli in it and a count of 1, and its dashed row is
   gone.

For [[open-project-into-group]], which now holds the screen half, the menu wording is "New Project…" above a divider. The sheet's
group line is its title, "New project in <group>", with the group name in `Theme.tx2`.

The task is `status: done`: you approved v1 on 2026-10-12, so every Done when item is ticked.
The demo file is `.notebook/blocks/new-project-in-group-design-demo.md`.

It leaves three things out on purpose: a group picker in the sheet, Open Project… into a group, and
any change to the + menu or File › New Project…. All three follow
[[2026-10-12-group-context-menu-entry]].

This isn't on a `/design` canvas. This session had no `/design` skill, the Artifact tool here can't
make a canvas from the Design type, and listing types returned none. The designer skill's other
option for a native app, one published HTML page, is what you get.

## Verification

- `swift run shots <scratchpad>/before` printed "shots written to …/before" (43 files). The frames are
  built on `board.png`, `setup-reading.png` and a crop of `new-project.png`. The positions of the rows
  I drew come from `ProjectSidebar+Groups.swift` and were measured against `board.png`: the group
  rule at x 85, rows 30pt tall, a 14pt end gap. Colours were sampled from the shots: sidebar
  `#0F1116`, rule `#222733`, selection `#181C24`/`#2C323F`.
- Headless Chrome at 1280 wide: all six frames render and nothing is clipped. On the first look,
  a sliver of yongkang's old selection outline showed, and the redrawn names were lighter than
  SwiftUI's. I widened the patch and dropped `-webkit-font-smoothing: antialiased`, and a second
  render matched.
- Headless Chrome with the page in a 400px-wide iframe: no sideways scroll, and the frames stack
  one per row.
- Artifact publish returned Version 1 at the URL above.
- `make check` wasn't run, because no Swift or app code changed. The app's own screens are unchanged,
  so there's no before-and-after shot difference to name.

## Review

```json
{
  "summary": "Published a six-frame demo of New Project… on a sidebar group's menu, the sheet naming the group in its title, and where it lands.",
  "confidence": "high",
  "confidence_why": "Entry point already decided; frames drawn over real shots.",
  "touches": "Notebook demo and task",
  "changed": [
    "A demo link shows six frames of the new flow",
    "The design task is done, approved, every Done when item ticked",
    "A demo file waits in Blocks for your approval"
  ],
  "checks": [
    {"claim": "Shots render today's screens", "status": "passed", "result": "shots written, 43 files",
     "command": "swift run shots <scratchpad>/before → shots written to …/before"},
    {"claim": "Demo fits desktop width", "status": "passed", "result": "six frames, nothing clipped at 1280",
     "command": "Chrome --headless --window-size=1280,3400 --screenshot preview.html → desktop.png"},
    {"claim": "Demo fits phone width", "status": "passed", "result": "no sideways scroll in a 400px frame",
     "command": "Chrome --headless --screenshot phonewrap.html (400px iframe) → phone2.png"},
    {"claim": "Demo is published", "status": "passed", "result": "Version 1 at artifact TgZ4tim2CrmoJqdHAwiv7H",
     "command": "Artifact publish → https://claude.ai/artifact/TgZ4tim2CrmoJqdHAwiv7H (Version 1)"},
    {"claim": "Build and tests pass", "status": "not_run", "result": "no code changed",
     "command": "make check"}
  ],
  "holds": [
    "No Swift or app code changed, only notebook files and a published page.",
    "Each frame is a real shot, so everything not outlined is today's app."
  ],
  "shows": [
    {"kind": "ui", "title": "New project in a group",
     "after": "https://claude.ai/artifact/TgZ4tim2CrmoJqdHAwiv7H",
     "highlight": [".new"],
     "note": "A published page, not a served app: the macOS app can't run in a browser."}
  ],
  "spots": [],
  "questions": [],
  "concerns": [
    {"title": "Not on a /design canvas",
     "detail": "This session had no /design skill or Design type, so the demo is one published HTML page.",
     "blocks": false}
  ],
  "outside": [
    {"kind": "write", "what": "Published the demo and three shot PNGs to claude.ai artifact TgZ4tim2CrmoJqdHAwiv7H"},
    {"kind": "read", "what": "Read the earlier design canvas CUC1Ld7B2cxZc3nFTrhCi3 and listed Artifact types"},
    {"kind": "local", "what": "Rendered shots and headless Chrome screenshots into the session scratchpad"}
  ],
  "files": [
    {"path": ".notebook/tasks/new-project-in-group-design.md", "why": "Status designing, three Done when ticked"},
    {"path": ".notebook/blocks/new-project-in-group-design-demo.md", "why": "The demo waiting for your approval"},
    {"path": ".notebook/runs/3bd68cdb-e2b4-4c41-a07f-2d8cb40ca4ca-work-new-project-in-group-design.md", "why": "This report"}
  ],
  "next": "Approval unblocks the screen half of open-project-into-group."
}
```
