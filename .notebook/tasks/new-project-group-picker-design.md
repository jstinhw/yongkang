---
id: new-project-group-picker-design
kind: task
title: "Design the sheet's group picker"
status: done
depends_on: [new-project-in-group-design]
designer: Allen
project: new-project-in-group
owner: ""
created: 2026-10-12
updated: 2026-10-12
external: {}
---

The New Project sheet gains a control for which group the project joins, starting on no group
when opened from the + menu or File > New Project…. This adds that one change to the approved
new-project-in-group demo.

## Done when

- [x] The demo shows the sheet opened from the + menu with the group control on no group, and
      what "no group" is called there.
- [x] The demo shows the control open, listing the sidebar's groups in their order, a pending
      empty group among them, and no group.
- [x] The demo shows the sheet opened from a group's **New Project…**, with the control already
      on that group, and what becomes of the "New project in <group>" title next to it.
- [x] The demo shows the sheet when no group exists: no control, as today.
- [x] The user has approved the demo.

## Context

The user asked for this in their own words: in the + create-project sheet, let them select the
group, defaulting to no group ([[2026-10-12-group-picker-in-sheet]]). Build on the last approved
demo from [[new-project-in-group-design]], which settled the group context menu and the
"New project in <group>" title; mock it in Claude Code's native `/design` skill, never the gstack
`design-*` skills. Today's sheet is `Sources/YongkangUI/Features/Home/NewProjectForm.swift`: a
title row with the agent picker on its right, the "Describe it" prompt, then Cancel and Create.

Open for the demo to settle: where the control sits (title row, beside the agent picker, or a row
of its own) and whether the title keeps naming the group once the control does.

What crosses to [[new-project-group-picker]]: the control's place and kind, its label and its
wording for no group, and the title as approved.
