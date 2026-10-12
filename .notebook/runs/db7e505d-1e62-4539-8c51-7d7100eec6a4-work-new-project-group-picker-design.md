---
kind: run
session: db7e505d-1e62-4539-8c51-7d7100eec6a4
task: new-project-group-picker-design
work_id: new-project-group-picker-design
title: "Design the sheet's group picker"
status: done
paths: [.notebook/tasks/new-project-group-picker-design.md, .notebook/blocks/new-project-group-picker-design-demo.md, .notebook/runs/db7e505d-1e62-4539-8c51-7d7100eec6a4-work-new-project-group-picker-design.md]
report: "Design canvas of the sheet's group button published and approved; task done."
started_at: 2026-10-12T13:25:00Z
finished_at: 2026-10-12T13:46:00Z
---

## Result

The demo is a design canvas at https://claude.ai/artifact/AXrnqMytyf4bqSdGKRANRV. It has five
frames in three rows. Each one is today's app from `swift run shots`, with the new control drawn
over it, and two stickies beside the frames.

1. **Opened from the + menu.** The title row gets a second button, left of the agent picker and
   drawn like it: a stack icon, **No group**, the up-down chevrons. Beside it is the sheet with no
   groups at all, which has no button and is the same as today.
2. **Picking a group.** The button is open over the whole window, so the list can be checked
   against the sidebar. It's a plain menu: No group with a tick, a divider, then Client work and
   Side projects. Side projects is the empty group just named from the + menu, last in the list
   just as it's last in the sidebar.
3. **Opened from a group.** From Client work's New Project…, the button starts on Client work.
   The title goes back to "New project". Beside it is today's sheet with the approved v1 title,
   "New project in Client work", for comparison.

The two things the task left open, as the demo settles them:

- **Where the control sits:** in the title row, beside the agent picker.
- **The title:** it stops naming the group, because the button names it in the same row.

What crosses to [[new-project-group-picker]]:

- The button is in `ConsoleButtonStyle` and opens a menu.
- Its words are "No group", and "Group for this project" for VoiceOver.
- It isn't shown when no group exists, empty ones included.
- A long name is cut short in the button, never the agent picker.

The task is `status: done`: you approved v1 on 2026-10-12, so every Done when item is ticked,
and [[new-project-group-picker]] was built on it. The demo file is
`.notebook/blocks/new-project-group-picker-design-demo.md`.

This time the demo is on the Design canvas the project asks for. The approved v1 was a plain page
because no canvas could be made in that session. The page and ink are the same as v1's.

## Verification

- `swift run shots <scratchpad>/before` printed "shots written to …/before" (44 files). The frames
  are built on `board.png`, `new-project.png` and `new-project-group.png`. The sheet is cropped at
  (190, 324, 520×252) pt. The button's place and size come from the agent picker in the shot:
  x 367.5–497.5, y 22.5–51.5 in the sheet, 30 pt tall. Its colours are `Theme.raised`
  `#171C25`, `Theme.controlLine` `#262D3A`, `Theme.prose` `#C7D0DC`, `tx2`/`tx3` for the icons.
- Artifact quickstart (design) returned the Design type. A Design System listing returned none,
  so the canvas uses the app's own ink.
- Three PNGs were uploaded as canvas assets. canvas.json and five artboards were published:
  Versions 2–6, ending at version id 1791812621-4bf2.
- Each artboard's markup was rendered with headless Chrome at 2×, with the local shots in place
  of the uploads (`check/*.png`). The No group and Client work buttons line up with the agent
  picker. The open list reads No group ✓ / Client work / Side projects, and the pointer doesn't
  cover a name. Nothing is clipped.
- Before moving to the canvas, the same frames were checked as a plain HTML page at 1280 and
  390 px wide. At 390 they stacked one per row with no sideways scroll. The canvas itself pans and
  zooms, so it has no phone layout to check.
- `make check` wasn't run, because no Swift or app code changed. Nothing in the app changed, so
  there's no before-and-after shot difference.

## Review

```json
{
  "summary": "Published a design canvas showing a group button beside the New Project sheet's agent picker, starting on No group, with its list.",
  "confidence": "high",
  "confidence_why": "Readings were already decided; frames drawn over real shots.",
  "touches": "Notebook demo and task",
  "changed": [
    "A design canvas link shows five frames of the sheet's group button",
    "The design task is done, approved, every Done when item ticked",
    "The demo file in Blocks is approved and done"
  ],
  "checks": [
    {"claim": "Shots render today's screens", "status": "passed", "result": "shots written, 44 files",
     "command": "swift run shots <scratchpad>/before → shots written to …/before"},
    {"claim": "Canvas is published", "status": "passed", "result": "Version 6 at AXrnqMytyf4bqSdGKRANRV",
     "command": "Artifact publish ×5 → https://claude.ai/artifact/AXrnqMytyf4bqSdGKRANRV (Version 6)"},
    {"claim": "Each frame draws as meant", "status": "passed", "result": "five frames, button aligned, nothing clipped",
     "command": "Chrome --headless --force-device-scale-factor=2 --screenshot check/<frame>.html → check/<frame>.png"},
    {"claim": "Frames fit phone width", "status": "not_run", "result": "a canvas pans and zooms; HTML preview passed",
     "command": "Chrome --headless --screenshot phonewrap.html (390px iframe of the HTML preview) → phone.png"},
    {"claim": "Build and tests pass", "status": "not_run", "result": "no code changed",
     "command": "make check"}
  ],
  "holds": [
    "No Swift or app code changed, only notebook files and a published canvas.",
    "Each frame is a real shot, so everything but the button and menu is today's app."
  ],
  "spots": [],
  "questions": [],
  "concerns": [
    {"title": "Title stops naming the group",
     "detail": "v1's \"New project in Client work\" becomes \"New project\" because the button names it. Say if you want both.",
     "blocks": false},
    {"title": "A new icon for groups",
     "detail": "Groups have no icon in the sidebar; the button uses a stack symbol so it reads as a group. Say if none.",
     "blocks": false}
  ],
  "outside": [
    {"kind": "write", "what": "Created design canvas AXrnqMytyf4bqSdGKRANRV on claude.ai: five artboards, canvas.json, three shot PNGs"},
    {"kind": "read", "what": "Read the approved v1 demo TgZ4tim2CrmoJqdHAwiv7H, the Design quickstart and the Design System listing"},
    {"kind": "local", "what": "Rendered shots and headless Chrome screenshots into the session scratchpad"}
  ],
  "files": [
    {"path": ".notebook/tasks/new-project-group-picker-design.md", "why": "Status done, every Done when ticked"},
    {"path": ".notebook/blocks/new-project-group-picker-design-demo.md", "why": "The demo you approved"},
    {"path": ".notebook/runs/db7e505d-1e62-4539-8c51-7d7100eec6a4-work-new-project-group-picker-design.md", "why": "This report"}
  ],
  "next": "Approval unblocks new-project-group-picker, building the button in the sheet."
}
```
