---
id: new-project-group-picker-design-demo
kind: demo
title: "Design the sheet's group picker"
status: done
task: new-project-group-picker-design
session: db7e505d-1e62-4539-8c51-7d7100eec6a4
branch: approve-request
before:
url: https://claude.ai/artifact/AXrnqMytyf4bqSdGKRANRV
serve:
action: "Approve this, or say what is wrong with it."
created: 2026-10-12
updated: 2026-10-12
---

In the + create-project sheet, let you pick the group, with no group picked to start. This
builds on the approved "New project in a group" demo.

## What changes

- The sheet's title row gets a second button, left of the agent picker and drawn the same way:
  a stack icon, the group's name, the up-down chevrons.
- From the + menu or File › New Project… it reads **No group**.
- Clicking it opens a plain menu: No group with a tick, a divider, then every group in sidebar
  order. An empty group just named from the + menu is in that list too, last, where the sidebar
  shows it.
- From a group's **New Project…** it starts on that group, and you can change it there.
- The title is "New project" however the sheet opens. The approved "New project in Client work"
  title is dropped, because the button already names the group in the same row.
- With no groups at all there is no button, and the sheet is the same as today.
- Not yet: no way to make a group from the sheet (New Group… on the + menu still does that), and
  no Open Project… into a group.

## Revisions

- v1 · design canvas, five frames over today's shots: + menu, no groups, the list open, from a group, today's v1 title · https://claude.ai/artifact/AXrnqMytyf4bqSdGKRANRV
