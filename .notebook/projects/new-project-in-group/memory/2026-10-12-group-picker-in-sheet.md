---
id: 2026-10-12-group-picker-in-sheet
kind: memory
title: "Pick the group in the sheet"
memory_type: decision
source: user
project: new-project-in-group
subject: new-project-group-picker
supersedes: []
created: 2026-10-12
updated: 2026-10-12
---

The user asked for the New Project sheet opened from the sidebar's + menu to let them choose
the group, with no group selected by default. This adds the group picker that
[[2026-10-12-group-context-menu-entry]] left out; the group's context menu entry stays.

Readings taken where the request was silent:

- File > New Project… opens the same sheet, so it gets the same picker, also on no group.
- Opened from a group's **New Project…**, the picker starts on that group, so that entry still
  does what the approved demo showed; the user can change it there.
- The picker lists every group in sidebar order, plus a pending empty group if there is one.
  It does not create a group: **New Group…** on the + menu still does that.
- With no groups at all, the picker is not shown, so a first-run sheet looks as it does today.
